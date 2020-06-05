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

  @doc """
  Start a new supervised queue

  By default this starts a new supervised queue across all nodes running Oban on the same database
  and prefix. You can pass the option `local_only: true` if you prefer to start the queue only on
  the local node.

  ## Options

  * `queue` - specifies the queue name
  * `limit` - set the concurrency limit
  * `local_only` - specifies if the queue will be started only on the local node, default: `false`

  ## Examples

  Start the `:priority` queue with a concurrency limit of 10 across the connected nodes.

      Oban.start_queue(config, queue: :priority, limit: 10)
      :ok

  Start the `:media` queue with a concurrency limit of 5 only on the local node.

      Oban.start_queue(config, queue: :media, limit: 5, local_only: true)
      :ok
  """
  @doc since: "2.0.0"
  @spec start_queue(Config.t(), opts :: Keyword.t()) :: :ok
  def start_queue(%Config{name: name} = conf, opts)
      when is_list(opts) do
    Enum.each(opts, &validate_queue_opt!/1)

    queue = Keyword.fetch!(opts, :queue)
    limit = Keyword.fetch!(opts, :limit)

    if Keyword.get(opts, :local_only) do
      name
      |> child_name()
      |> send(
        {:notification, :signal,
         %{"action" => "start", "queue" => to_string(queue), "limit" => limit}}
      )

      :ok
    else
      Notifier.notify(conf, :signal, %{action: :start, queue: queue, limit: limit})
    end
  end

  @doc """
  Shutdown a queue's supervision tree and stop running jobs for that queue

  By default this action will occur across all the running nodes. Still, if you prefer to stop the
  queue's supervision tree and stop running jobs for that queue only on the local node, you can
  pass the option: `local_only: true`

  The shutdown process pauses the queue first and allows current jobs to exit gracefully, provided
  they finish within the shutdown limit.

  ## Options

  * `queue` - specifies the queue name
  * `local_only` - specifies if the queue will be stopped only on the local node, default: `false`

  ## Examples

      Oban.stop_queue(config, queue: :default)
      :ok

      Oban.stop_queue(config, queue: :media, local_only: true)
      :ok
  """

  @doc since: "2.0.0"
  @spec stop_queue(Config.t(), opts :: Keyword.t()) :: :ok
  def stop_queue(%Config{name: name} = conf, opts) when is_list(opts) do
    Enum.each(opts, &validate_queue_opt!/1)

    queue = Keyword.fetch!(opts, :queue)

    if Keyword.get(opts, :local_only) do
      name
      |> child_name()
      |> send({:notification, :signal, %{"action" => "stop", "queue" => to_string(queue)}})

      :ok
    else
      Notifier.notify(conf, :signal, %{action: :stop, queue: queue})
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
