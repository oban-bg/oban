defmodule Oban.Midwife do
  @moduledoc false

  use GenServer

  alias Oban.{Config, Notifier, Registry}
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
    Notifier.listen(conf.name, [:signal])

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:notification, :signal, payload}, %State{conf: conf} = state) do
    case payload do
      %{"action" => "start"} ->
        conf.name
        |> Registry.via()
        |> Supervisor.start_child(queue_spec(conf, payload))

      %{"action" => "stop"} ->
        %{id: child_id} = queue_spec(conf, payload)

        Supervisor.terminate_child(Registry.via(conf.name), child_id)
        Supervisor.delete_child(Registry.via(conf.name), child_id)

      _ ->
        :ok
    end

    {:noreply, state}
  end

  def handle_info(_message, state) do
    {:noreply, state}
  end

  defp queue_spec(conf, %{"queue" => queue} = payload) do
    spec_opts =
      payload
      |> Map.drop(["action", "ident", "local_only"])
      |> Keyword.new(fn {key, val} -> {String.to_existing_atom(key), val} end)

    QueueSupervisor.child_spec({queue, spec_opts}, conf)
  end
end
