defmodule Oban.Plugins.Stager do
  @moduledoc """
  Transition jobs to the `:available` state when:

  * jobs are `:scheduled` and the current time is on or after the timestamp specified in `:scheduled_at`.
  * jobs are `:retryable` and they don't reach the attempt limit specified by `:max_attempts`.

  Besides changing the state of jobs, this plugin also uses PubSub to notify queues that they have
  available jobs. This prevents every queue from polling independently and reduces database load.

  This module is necessary for the execution of scheduled and retryable jobs. As such, it's started
  by each Oban instance automatically unless `plugins: false` is specified.

  ## Options

  * `:interval` - the number of milliseconds between database updates. This is directly tied to
    the resolution of _scheduled_ jobs. For example, with an `interval` of `5_000ms`, scheduled
    jobs are checked every 5 seconds. The default is `1_000ms`.
  * `:limit` — the number of jobs that will be staged each time the plugin runs. Defaults to
    `5,000`, which you can increase if staging can't keep up with your insertion rate or decrease
    if you're experiencing staging timeouts.

  ## Instrumenting with Telemetry

  The `Oban.Plugins.Stager` plugin adds the following metadata to the `[:oban, :plugin, :stop]` event:

  * `:staged_count` - the number of jobs that were staged in the database
  """

  @behaviour Oban.Plugin

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

  alias Oban.{Job, Notifier, Peer, Plugin, Repo, Validation}

  @type option :: Plugin.option() | {:interval, pos_integer()}

  defmodule State do
    @moduledoc false

    defstruct [
      :conf,
      :name,
      :timer,
      limit: 5_000,
      interval: :timer.seconds(1)
    ]
  end

  @impl Plugin
  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  @impl Plugin
  def validate(opts) do
    Validation.validate(opts, fn
      {:conf, _} -> :ok
      {:name, _} -> :ok
      {:interval, interval} -> Validation.validate_integer(:interval, interval)
      {:limit, limit} -> Validation.validate_integer(:limit, limit)
      option -> {:error, "unknown option provided: #{inspect(option)}"}
    end)
  end

  @impl GenServer
  def init(opts) do
    Validation.validate!(opts, &validate/1)

    Process.flag(:trap_exit, true)

    state =
      State
      |> struct!(opts)
      |> schedule_staging()

    :telemetry.execute([:oban, :plugin, :init], %{}, %{conf: state.conf, plugin: __MODULE__})

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
    if Peer.leader?(state.conf) do
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
      |> order_by(asc: :id)
      |> limit(^state.limit)
      |> lock("FOR UPDATE SKIP LOCKED")

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

  # Scheduling

  defp schedule_staging(state) do
    timer = Process.send_after(self(), :stage, state.interval)

    %{state | timer: timer}
  end
end
