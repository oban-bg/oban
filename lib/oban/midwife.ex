defmodule Oban.Midwife do
  @moduledoc false

  use GenServer

  alias Oban.{Config, Notifier}
  alias Oban.Queue.Supervisor, as: QueueSupervisor

  @type option :: {:name, module()} | {:conf, Config.t()}

  defmodule State do
    @moduledoc false

    defstruct [:conf]
  end

  @spec start_link([option]) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)

    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec start_queue(Config.t(), opts :: Keyword.t()) :: :ok
  def start_queue(%Config{name: name} = conf, [_ | _] = opts) do
    Enum.each(opts, &validate_queue_opt!/1)

    queue = Keyword.fetch!(opts, :queue)
    limit = Keyword.fetch!(opts, :limit)
    payload = %{"action" => "start", "queue" => to_string(queue), "limit" => limit}

    if Keyword.get(opts, :local_only) do
      name
      |> child_name()
      |> send({:notification, :signal, payload})

      :ok
    else
      Notifier.notify(conf, :signal, payload)
    end
  end

  @spec stop_queue(Config.t(), opts :: Keyword.t()) :: :ok
  def stop_queue(%Config{name: name} = conf, [_ | _] = opts) do
    Enum.each(opts, &validate_queue_opt!/1)

    queue = Keyword.fetch!(opts, :queue)
    payload = %{"action" => "stop", "queue" => to_string(queue)}

    if Keyword.get(opts, :local_only) do
      name
      |> child_name()
      |> send({:notification, :signal, payload})

      :ok
    else
      Notifier.notify(conf, :signal, payload)
    end
  end

  @impl GenServer
  def init(opts) do
    {:ok, struct!(State, opts), {:continue, :start}}
  end

  @impl GenServer
  def handle_continue(:start, %State{conf: conf} = state) do
    conf.name
    |> Module.concat("Notifier")
    |> Notifier.listen([:signal])

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:notification, :signal, payload}, %State{conf: conf} = state) do
    case payload do
      %{"action" => "start", "queue" => queue, "limit" => limit} ->
        Supervisor.start_child(conf.name, queue_spec(queue, limit, conf))

      %{"action" => "stop", "queue" => queue} ->
        %{id: child_id} = queue_spec(queue, 0, conf)

        Supervisor.terminate_child(conf.name, child_id)
        Supervisor.delete_child(conf.name, child_id)

      _ ->
        :ok
    end

    {:noreply, state}
  end

  def handle_info(_message, state) do
    {:noreply, state}
  end

  defp queue_spec(queue, limit, conf) do
    QueueSupervisor.child_spec({queue, limit}, conf)
  end

  defp child_name(name), do: Module.safe_concat(name, "Midwife")

  defp validate_queue_opt!({:queue, queue}) do
    unless (is_atom(queue) and not is_nil(queue)) or (is_binary(queue) and byte_size(queue) > 0) do
      raise ArgumentError,
            "expected :queue to be a binary or atom (except `nil`), got: #{inspect(queue)}"
    end
  end

  defp validate_queue_opt!({:limit, limit}) do
    unless is_integer(limit) and limit > 0 do
      raise ArgumentError, "expected :limit to be a positive integer, got: #{inspect(limit)}"
    end
  end

  defp validate_queue_opt!({:local_only, local_only}) do
    unless is_boolean(local_only) do
      raise ArgumentError, "expected :local_only to be a boolean, got: #{inspect(local_only)}"
    end
  end

  defp validate_queue_opt!(option) do
    raise ArgumentError, "unknown option provided #{inspect(option)}"
  end
end
