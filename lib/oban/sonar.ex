defmodule Oban.Sonar do
  @moduledoc false

  use GenServer

  alias Oban.{Backoff, Notifier}
  alias __MODULE__, as: State

  require Logger

  defstruct [
    :conf,
    :timer,
    :interval,
    min_interval: :timer.seconds(5),
    max_interval: :timer.seconds(60),
    stale_after: :timer.seconds(120),
    nodes: %{},
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

    {:ok, %{state | interval: state.min_interval}, {:continue, :start}}
  end

  @impl GenServer
  def terminate(_reason, state) do
    if is_reference(state.timer), do: Process.cancel_timer(state.timer)

    :ok
  end

  @impl GenServer
  def handle_continue(:start, state) do
    listen_notify(state.conf)

    {:noreply, schedule_ping(state)}
  end

  @impl GenServer
  def handle_call(:get_nodes, _from, state) do
    {:reply, Map.keys(state.nodes), state}
  end

  def handle_call(:get_status, _from, state) do
    {:reply, state.status, state}
  end

  def handle_call(:ping, _from, state) do
    {:noreply, state} = handle_info(:ping, state)

    {:reply, :ok, state}
  end

  def handle_call(:prune_nodes, _from, state) do
    state = prune_stale_nodes(state)

    {:reply, Map.keys(state.nodes), state}
  end

  @impl GenServer
  def handle_info(:ping, state) do
    prev_status = state.status
    prev_nodes = Map.keys(state.nodes)

    listen_notify(state.conf)

    state =
      state
      |> prune_stale_nodes()
      |> update_status()

    changed? = state.status != prev_status or Map.keys(state.nodes) != prev_nodes

    state =
      state
      |> adjust_interval(changed?)
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

  def handle_info(message, state) do
    Logger.warning(
      [
        message: "Received unexpected message: #{inspect(message)}",
        source: :oban,
        module: __MODULE__
      ],
      domain: [:oban]
    )

    {:noreply, state}
  end

  # Helpers

  defp listen_notify(conf) do
    Notifier.listen(conf, :sonar)
    Notifier.notify(conf, :sonar, %{node: conf.node, ping: true})
  catch
    :exit, _ -> :ok
  end

  defp schedule_ping(state) do
    timer = Process.send_after(self(), :ping, Backoff.jitter(state.interval))

    %{state | timer: timer}
  end

  defp adjust_interval(state, true), do: %{state | interval: state.min_interval}

  defp adjust_interval(state, false) do
    target =
      case state.status do
        # Clustered scales with peer count becuase peer pings prove liveness
        :clustered ->
          peer_count = max(map_size(state.nodes), 1)
          min(state.min_interval * peer_count, state.max_interval)

        :solitary ->
          state.max_interval

        _ ->
          state.min_interval
      end

    %{state | interval: min(state.interval * 2, target)}
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
    stime = System.monotonic_time(:millisecond)
    nodes = Map.reject(state.nodes, fn {_, recorded} -> stime - recorded > state.stale_after end)

    %{state | nodes: nodes}
  end
end
