defmodule Oban.Sonar do
  @moduledoc false

  use GenServer

  alias Oban.Notifier
  alias __MODULE__, as: State

  defstruct [
    :conf,
    :timer,
    interval: :timer.seconds(15),
    nodes: %{},
    stale_mult: 2,
    status: :unknown
  ]

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)

    conf = Keyword.fetch!(opts, :conf)

    if conf.testing != :disabled do
      :ignore
    else
      GenServer.start_link(__MODULE__, struct!(State, opts), name: name)
    end
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
    :ok = Notifier.notify(state.conf, :sonar, %{node: state.conf.node, ping: :ping})

    {:noreply, schedule_ping(state)}
  end

  @impl GenServer
  def handle_call(:get_status, _from, state) do
    {:reply, state.status, state}
  end

  def handle_call(:prune_nodes, _from, state) do
    state = prune_stale_nodes(state)

    {:reply, state.nodes, state}
  end

  @impl GenServer
  def handle_info(:ping, state) do
    :ok = Notifier.notify(state.conf, :sonar, %{node: state.conf.node, ping: true})

    state =
      state
      |> prune_stale_nodes()
      |> update_status()
      |> schedule_ping()

    {:noreply, state}
  end

  def handle_info({:notification, :sonar, %{"node" => node} = payload}, state) do
    time = Map.get(payload, "time", System.monotonic_time(:millisecond))

    state =
      state
      |> Map.update!(:nodes, &Map.put(&1, node, time))
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
        [] -> :isolated
        [^node] -> :solitary
        [_ | _] -> :clustered
      end

    if status != state.status do
      :telemetry.execute([:oban, :notifier, :switch], %{}, %{conf: state.conf, status: status})
    end

    %{state | status: status}
  end

  defp prune_stale_nodes(state) do
    stale = System.monotonic_time(:millisecond) + state.interval * state.stale_mult
    nodes = Map.reject(state.nodes, fn {_, recorded} -> recorded > stale end)

    %{state | nodes: nodes}
  end
end
