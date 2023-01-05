defmodule Oban.Stager do
  @moduledoc false

  use GenServer

  import Ecto.Query,
    only: [
      distinct: 2,
      join: 5,
      limit: 2,
      lock: 2,
      order_by: 2,
      select: 3,
      where: 3
    ]

  alias Oban.{Job, Notifier, Peer, Plugin, Repo}

  require Logger

  @type option :: Plugin.option() | {:interval, pos_integer()}

  defmodule State do
    @moduledoc false

    defstruct [
      :conf,
      :name,
      :timer,
      interval: :timer.seconds(1),
      limit: 5_000,
      mode: :global,
      ping_at_tick: 0,
      swap_at_tick: 5,
      tick: 0
    ]
  end

  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  @impl GenServer
  def init(opts) do
    conf = Keyword.fetch!(opts, :conf)
    state = %State{conf: conf, interval: conf.stage_interval, name: opts[:name]}

    # Stager is no longer a plugin, but init event is essential for auto-allow and backward
    # compatibility.
    :telemetry.execute([:oban, :plugin, :init], %{}, %{conf: state.conf, plugin: __MODULE__})

    if state.interval == :infinity do
      :ignore
    else
      Process.flag(:trap_exit, true)

      {:ok, state, {:continue, :start}}
    end
  end

  @impl GenServer
  def handle_continue(:start, %State{} = state) do
    Notifier.listen(state.conf.name, :stager)

    state =
      state
      |> schedule_staging()
      |> check_notify_mode()

    {:noreply, state}
  end

  @impl GenServer
  def terminate(_reason, %State{timer: timer}) do
    if is_reference(timer), do: Process.cancel_timer(timer)

    :ok
  end

  @impl GenServer
  def handle_info(:stage, %State{} = state) do
    meta = %{conf: state.conf, plugin: __MODULE__}

    :telemetry.span([:oban, :plugin], meta, fn ->
      case check_leadership_and_stage(state) do
        {:ok, extra} when is_map(extra) ->
          {:ok, Map.merge(meta, extra)}

        error ->
          {:error, Map.put(meta, :error, error)}
      end
    end)

    state =
      state
      |> schedule_staging()
      |> check_notify_mode()

    {:noreply, state}
  end

  def handle_info({:notification, :stager, _payload}, %State{} = state) do
    if state.mode == :local do
      Logger.info("Oban job staging switched back to global mode.")
    end

    {:noreply, %{state | ping_at_tick: 60, mode: :global, swap_at_tick: 65, tick: 0}}
  end

  defp check_leadership_and_stage(state) do
    leader? = Peer.leader?(state.conf)

    Repo.transaction(state.conf, fn ->
      counts = stage_scheduled(state, leader?: leader?)

      notify_queues(state, leader?: leader?)

      counts
    end)
  end

  defp stage_scheduled(state, leader?: true) do
    subquery =
      Job
      |> where([j], j.state in ["scheduled", "retryable"])
      |> where([j], not is_nil(j.queue))
      |> where([j], j.scheduled_at <= ^DateTime.utc_now())
      |> order_by(asc: :id)
      |> limit(^state.limit)
      |> lock("FOR UPDATE SKIP LOCKED")

    query =
      Job
      |> join(:inner, [j], x in subquery(subquery), on: j.id == x.id)
      |> select([_j, x], map(x, [:id, :queue, :state, :worker]))

    {staged_count, staged} = Repo.update_all(state.conf, query, set: [state: "available"])

    %{staged_count: staged_count, staged_jobs: staged}
  end

  defp stage_scheduled(_state, _leader), do: 0

  defp notify_queues(%State{conf: conf, mode: :global}, leader?: true) do
    query =
      Job
      |> where([j], j.state == "available")
      |> where([j], not is_nil(j.queue))
      |> select([j], %{queue: j.queue})
      |> distinct(true)

    payload = Repo.all(conf, query)

    Notifier.notify(conf, :insert, payload)
  end

  defp notify_queues(%State{conf: conf, mode: :local}, _leader) do
    match = [{{{conf.name, {:producer, :"$1"}}, :"$2", :_}, [], [{{:"$1", :"$2"}}]}]

    for {queue, pid} <- Registry.select(Oban.Registry, match) do
      send(pid, {:notification, :insert, %{"queue" => queue}})
    end
  end

  defp notify_queues(_state, _leader), do: :ok

  # Scheduling

  defp schedule_staging(state) do
    timer = Process.send_after(self(), :stage, state.interval)

    %{state | timer: timer}
  end

  defp check_notify_mode(state) do
    if state.tick >= state.ping_at_tick do
      Notifier.notify(state.conf.name, :stager, %{ping: :pong})
    end

    if state.mode == :global and state.tick == state.swap_at_tick do
      Logger.info("""
      Oban job staging switched to local mode.

      Local mode places more load on the database because each queue polls for jobs every second.
      To restore global mode, ensure notifications work or switch to the PG notifier.
      """)

      %{state | mode: :local}
    else
      %{state | tick: state.tick + 1}
    end
  end
end
