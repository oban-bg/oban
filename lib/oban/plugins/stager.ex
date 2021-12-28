defmodule Oban.Plugins.Stager do
  @moduledoc """
  Transition jobs to the `available` state when they reach their scheduled time.

  This module is necessary for the execution of scheduled and retryable jobs.

  ## Options

  * `:interval` - the number of milliseconds between database updates. This is directly tied to
    the resolution of _scheduled_ jobs. For example, with an `interval` of `5_000ms`, scheduled
    jobs are checked every 5 seconds. The default is `1_000ms`.
  * `:limit` — the number of jobs that will be staged each time the plugin runs. Defaults to
    `5,000`, which you can increase if staging can't keep up with your insertion rate or decrease
    if you're experiencing staging timeouts.

  ## Instrumenting with Telemetry

  The `Oban.Plugins.Stager` plugin adds the following metadata to the `[:oban, :plugin, :stop]` event:

  * :staged_count - the number of jobs that were staged in the database
  """

  use GenServer

  import Ecto.Query,
    only: [
      distinct: 2,
      join: 5,
      limit: 2,
      select: 3,
      where: 3
    ]

  alias Oban.{Config, Job, Notifier, Repo, Senator}

  @type option :: {:conf, Config.t()} | {:name, GenServer.name()} | {:interval, pos_integer()}

  defmodule State do
    @moduledoc false

    defstruct [
      :conf,
      :name,
      :timer,
      limit: 5_000,
      interval: :timer.seconds(1),
      lock_key: 1_149_979_440_242_868_003
    ]
  end

  @doc false
  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  @impl GenServer
  def init(opts) do
    Process.flag(:trap_exit, true)

    state =
      State
      |> struct!(opts)
      |> schedule_staging()

    {:ok, state}
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
        {:ok, staged_count} when is_integer(staged_count) ->
          {:ok, Map.put(meta, :staged_count, staged_count)}

        error ->
          {:error, Map.put(meta, :error, error)}
      end
    end)

    {:noreply, schedule_staging(state)}
  end

  defp check_leadership_and_stage(state) do
    if Senator.leader?(state.conf) do
      Repo.transaction(state.conf, fn ->
        {sched_count, nil} = stage_scheduled(state)

        notify_queues(state)

        sched_count
      end)
    else
      {:ok, 0}
    end
  end

  defp stage_scheduled(state) do
    subquery =
      Job
      |> where([j], j.state in ["scheduled", "retryable"])
      |> where([j], not is_nil(j.queue))
      |> where([j], j.scheduled_at <= ^DateTime.utc_now())
      |> limit(^state.limit)

    Repo.update_all(
      state.conf,
      join(Job, :inner, [j], x in subquery(subquery), on: j.id == x.id),
      set: [state: "available"]
    )
  end

  defp notify_queues(state) do
    query =
      Job
      |> where([j], j.state == "available")
      |> where([j], not is_nil(j.queue))
      |> select([j], %{queue: j.queue})
      |> distinct(true)

    payload = Repo.all(state.conf, query)

    Notifier.notify(state.conf, :insert, payload)
  end

  defp schedule_staging(state) do
    timer = Process.send_after(self(), :stage, state.interval)

    %{state | timer: timer}
  end
end
