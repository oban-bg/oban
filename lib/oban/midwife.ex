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

  This action starts a new supervised queue only on the local node.

  ## Examples

  Start the `:media` queue with a concurrency limit of 5 only on the local node.

      Oban.Midwife.start_queue(Oban, :media, 5)
      :ok
  """
  @doc since: "2.0.0"
  @spec start_queue(name :: atom(), queue :: Oban.queue_name(), limit :: pos_integer()) :: :ok
  def start_queue(name, queue, limit) do
    name
    |> child_name()
    |> send(
      {:notification, :signal,
       %{"action" => "start", "queue" => to_string(queue), "limit" => limit}}
    )

    :ok
  end

  @doc """
  Shutdown a queue's supervision tree and stop running jobs for given queue

  This action will occur only on the local node.

  The shutdown process pauses the queue first and allows current jobs to exit gracefully, provided
  they finish within the shutdown limit.

  ## Examples

      Oban.Midwife.stop_queue(Oban, :default)
      :ok
  """
  @doc since: "2.0.0"
  @spec stop_queue(name :: atom(), queue :: Oban.queue_name()) :: :ok
  def stop_queue(name, queue) do
    name
    |> child_name()
    |> send({:notification, :signal, %{"action" => "stop", "queue" => to_string(queue)}})

    :ok
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
end
