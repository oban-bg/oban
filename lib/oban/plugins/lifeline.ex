defmodule Oban.Plugins.Lifeline do
  @moduledoc """
  Naively transition jobs stuck `executing` back to `available`.

  The `Lifeline` plugin periodically rescues orphaned jobs, i.e. jobs that are stuck in the
  `executing` state because the node was shut down before the job could finish. Rescuing is
  purely based on time, rather than any heuristic about the job's expected execution time or
  whether the node is still alive.

  If an executing job has exhausted all attempts, the Lifeline plugin will mark it `discarded`
  rather than `available`.

  > #### 🌟 DynamicLifeline {: .info}
  >
  > This plugin may transition jobs that are genuinely `executing` and cause duplicate execution.
  > For more accurate rescuing or to rescue jobs that have exhausted retry attempts see the
  > `DynamicLifeline` plugin in [Oban Pro](https://getoban.pro/docs/pro/Oban.Pro.Plugins.DynamicLifeline.html).

  ## Using the Plugin

  Rescue orphaned jobs that are still `executing` after the default of 60 minutes:

      config :my_app, Oban,
        plugins: [Oban.Plugins.Lifeline],
        ...

  Override the default period to rescue orphans after a more aggressive period of 5 minutes:

      config :my_app, Oban,
        plugins: [{Oban.Plugins.Lifeline, rescue_after: :timer.minutes(5)}],
        ...

  ## Options

  * `:interval` — the number of milliseconds between rescue attempts. The default is `60_000ms`.

  * `:rescue_after` — the maximum amount of time, in milliseconds, that a job may execute before
  being rescued. 60 minutes by default, and rescuing is performed once a minute.

  ## Instrumenting with Telemetry

  The `Oban.Plugins.Lifeline` plugin adds the following metadata to the `[:oban, :plugin, :stop]`
  event:

  * `:rescued_jobs` — a list of jobs transitioned back to `available`

  * `:discarded_jobs` — a list of jobs transitioned to `discarded`

  _Note: jobs only include `id`, `queue`, `state` fields._
  """

  @behaviour Oban.Plugin

  use GenServer

  import Ecto.Query, only: [select: 3, where: 3]

  alias Oban.{Job, Peer, Plugin, Repo, Validation}
  alias __MODULE__, as: State

  @type option ::
          Plugin.option()
          | {:interval, timeout()}
          | {:rescue_after, pos_integer()}

  defstruct [
    :conf,
    :timer,
    interval: :timer.minutes(1),
    rescue_after: :timer.minutes(60)
  ]

  @doc false
  @spec child_spec(Keyword.t()) :: Supervisor.child_spec()
  def child_spec(opts), do: super(opts)

  @impl Plugin
  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)

    GenServer.start_link(__MODULE__, struct!(State, opts), name: name)
  end

  @impl Plugin
  def validate(opts) do
    Validation.validate_schema(opts,
      conf: :any,
      name: :any,
      interval: :pos_integer,
      rescue_after: :pos_integer
    )
  end

  @impl GenServer
  def init(state) do
    :telemetry.execute([:oban, :plugin, :init], %{}, %{conf: state.conf, plugin: __MODULE__})

    {:ok, schedule_rescue(state)}
  end

  @impl GenServer
  def terminate(_reason, %State{timer: timer}) do
    if is_reference(timer), do: Process.cancel_timer(timer)

    :ok
  end

  @impl GenServer
  def handle_info(:rescue, %State{} = state) do
    meta = %{conf: state.conf, plugin: __MODULE__}

    :telemetry.span([:oban, :plugin], meta, fn ->
      case check_leadership_and_rescue_jobs(state) do
        {:ok, extra} when is_map(extra) ->
          {:ok, Map.merge(meta, extra)}

        error ->
          {:error, Map.put(meta, :error, error)}
      end
    end)

    {:noreply, schedule_rescue(state)}
  end

  # Scheduling

  defp schedule_rescue(state) do
    timer = Process.send_after(self(), :rescue, state.interval)

    %{state | timer: timer}
  end

  # Rescuing

  defp check_leadership_and_rescue_jobs(state) do
    if Peer.leader?(state.conf) do
      Repo.transaction(state.conf, fn ->
        time = DateTime.add(DateTime.utc_now(), -state.rescue_after, :millisecond)
        base = where(Job, [j], j.state == "executing" and j.attempted_at < ^time)

        {rescued_count, rescued} = transition_available(base, state)
        {discard_count, discard} = transition_discarded(base, state)

        %{
          discarded_count: discard_count,
          discarded_jobs: discard,
          rescued_count: rescued_count,
          rescued_jobs: rescued
        }
      end)
    else
      {:ok, %{}}
    end
  end

  defp transition_available(base, state) do
    query =
      base
      |> where([j], j.attempt < j.max_attempts)
      |> select([j], map(j, [:id, :queue, :state]))

    Repo.update_all(state.conf, query, set: [state: "available"])
  end

  defp transition_discarded(base, state) do
    query =
      base
      |> where([j], j.attempt >= j.max_attempts)
      |> select([j], map(j, [:id, :queue, :state]))

    Repo.update_all(state.conf, query,
      set: [state: "discarded", discarded_at: DateTime.utc_now()]
    )
  end
end
