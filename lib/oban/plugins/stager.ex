defmodule Oban.Plugins.Stager do
  @moduledoc """
  Transition jobs to the `available` state when they reach their scheduled time.

  This module is necessary for the execution of scheduled and retryable jobs.

  ## Options

  * `:interval` - the number of milliseconds between database updates. This is directly tied to
    the resolution of _scheduled_ jobs. For example, with an `interval` of `5_000ms`, scheduled
    jobs are checked every 5 seconds. The default is `1_000ms`.

  ## Instrumenting with Telemetry

  The `Oban.Plugins.Stager` plugin adds the following metadata to the `[:oban, :plugin, :stop]` event:

  * :staged_count - the number of jobs that were staged in the database
  """

  use GenServer

  import Ecto.Query, only: [distinct: 2, from: 2, select: 2, subquery: 1, where: 3]

  alias Oban.{Config, Job, Query, Repo}

  @type option :: {:conf, Config.t()} | {:name, GenServer.name()}

  defmodule State do
    @moduledoc false

    defstruct [
      :conf,
      :name,
      :timer,
      interval: :timer.seconds(1),
      lock_key: 1_149_979_440_242_868_003
    ]
  end

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
      case lock_and_stage(state) do
        {:ok, staged_count} when is_integer(staged_count) ->
          {:ok, Map.put(meta, :staged_count, staged_count)}

        {:ok, false} ->
          {:ok, Map.put(meta, :staged_count, 0)}

        error ->
          {:error, Map.put(meta, :error, error)}
      end
    end)

    {:noreply, schedule_staging(state)}
  end

  defp lock_and_stage(state) do
    Query.with_xact_lock(state.conf, state.lock_key, fn ->
      {sched_count, nil} = stage_scheduled(state.conf)

      notify_queues(state.conf)

      sched_count
    end)
  end

  defp stage_scheduled(conf) do
    query =
      Job
      |> where([j], j.state in ["scheduled", "retryable"])
      |> where([j], not is_nil(j.queue))
      |> where([j], j.scheduled_at <= ^DateTime.utc_now())

    Repo.update_all(conf, query, set: [state: "available"])
  end

  @pg_notify "pg_notify(?, json_build_object('queue', ?)::text)"

  defp notify_queues(conf) do
    channel = "#{conf.prefix}.oban_insert"

    subquery =
      Job
      |> where([j], j.state == "available")
      |> where([j], not is_nil(j.queue))
      |> select([:queue])
      |> distinct(true)

    query = from job in subquery(subquery), select: fragment(@pg_notify, ^channel, job.queue)

    Repo.all(conf, query)

    :ok
  end

  defp schedule_staging(state) do
    timer = Process.send_after(self(), :stage, state.interval)

    %{state | timer: timer}
  end
end
