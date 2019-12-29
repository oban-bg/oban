defmodule Oban.Midwife do
  @moduledoc false

  use GenServer

  import Oban.Notifier, only: [signal: 0]

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
  def handle_info({:notification, signal(), payload}, %State{conf: conf} = state) do
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
end
