defmodule Oban.Sonar do
  @moduledoc false

  use GenServer

  alias Oban.Notifier
  alias __MODULE__, as: State

  @type status :: :disconnected | :isolated | :clustered

  defstruct [
    :conf,
    :timer,
    interval: :timer.seconds(30),
    nodes: %{},
    stale_mult: 2,
    status: :disconnected
  ]

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)

    GenServer.start_link(__MODULE__, struct!(State, opts), name: name)
  end

  @spec status(Oban.name()) :: status()
  def status(oban_name) do
    oban_name
    |> Oban.Registry.via(__MODULE__)
    |> GenServer.call(:get_status)
  end

  @impl GenServer
  def init(state) do
    Process.flag(:trap_exit, true)

    {:ok, state, {:continue, :start}}
  end

  @impl GenServer
  def terminate(_reason, state) do
    if is_reference(state.timer), do: Process.cancel_timer(state.timer)

    :ok
  end

  @impl GenServer
  def handle_continue(:start, state) do
    :ok = Notifier.listen(state.conf.name, :sonar)

    handle_info(:ping, state)
  end

  @impl GenServer
  def handle_call(:get_status, _from, state) do
    {:reply, state.status, state}
  end

  @impl GenServer
  def handle_info(:ping, state) do
    :ok = Notifier.notify(state.conf, :sonar, %{node: state.conf.node, ping: :ping})

    state =
      state
      |> prune_stale_nodes()
      |> update_status()
      |> schedule_ping()

    {:noreply, state}
  end

  def handle_info({:notification, :sonar, %{"node" => node, "ping" => _}}, state) do
    state =
      state
      |> Map.update!(:nodes, &Map.put(&1, node, System.system_time()))
      |> update_status()

    {:noreply, state}
  end

  # Helpers

  defp schedule_ping(state) do
    timer = Process.send_after(self(), :ping, state.interval)

    %{state | timer: timer}
  end

  defp update_status(state) do
    node = state.conf.node

    status =
      case Map.keys(state.nodes) do
        [] -> :disconnected
        [^node] -> :isolated
        [_ | _] -> :clustered
      end

    %{state | status: status}
  end

  defp prune_stale_nodes(state) do
    stale = System.system_time() - state.interval * state.stale_mult
    nodes = Map.reject(state.nodes, fn {_, recorded} -> recorded < stale end)

    %{state | nodes: nodes}
  end
end
