defmodule Oban.Plugins.Pruner do
  @moduledoc """
  Periodically delete completed, cancelled and discarded jobs based on age.

  ## Using the Plugin

  The following example demonstrates using the plugin without any configuration, which will prune
  jobs older than the default of 60 seconds:

      config :my_app, Oban,
        plugins: [Oban.Plugins.Pruner],
        ...

  Override the default options to prune jobs after 5 minutes:

      config :my_app, Oban,
        plugins: [{Oban.Plugins.Pruner, max_age: 300}],
        ...

  > #### 🌟 DynamicPruner {: .info}
  >
  > To prune on a cron-style schedule, retain jobs by a limit, or provide overrides for specific
  > queues, workers, and job states; see Oban Pro's [DynamicPruner][dyn].

  ## Options

  * `:interval` — the number of milliseconds between pruning attempts. The default is `30_000ms`.

  * `:limit` — the maximum number of jobs to prune at one time. The default is 10,000 to prevent
    request timeouts. Applications that steadily generate more than 10k jobs a minute should
    increase this value.

  * `:max_age` — the number of seconds after which a job may be pruned. Defaults to 60s.

  ## Instrumenting with Telemetry

  The `Oban.Plugins.Pruner` plugin adds the following metadata to the `[:oban, :plugin, :stop]` event:

  * `:pruned_jobs` - the jobs that were deleted from the database

  _Note: jobs only include `id`, `queue`, `state`, and `worker` fields._

  [dyn]: https://getoban.pro/docs/pro/dynamic_pruner.html.
  """

  @behaviour Oban.Plugin

  use GenServer

  import Ecto.Query, only: [join: 5, limit: 2, lock: 2, or_where: 3, select: 3]

  alias Oban.{Job, Peer, Plugin, Repo, Validation}

  @type option ::
          Plugin.option()
          | {:limit, pos_integer()}
          | {:max_age, pos_integer()}

  defmodule State do
    @moduledoc false

    defstruct [
      :conf,
      :name,
      :timer,
      interval: :timer.seconds(30),
      max_age: 60,
      limit: 10_000
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
      {:max_age, max_age} -> Validation.validate_integer(:max_age, max_age)
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
      |> schedule_prune()

    :telemetry.execute([:oban, :plugin, :init], %{}, %{conf: state.conf, plugin: __MODULE__})

    {:ok, state}
  end

  @impl GenServer
  def terminate(_reason, state) do
    if is_reference(state.timer), do: Process.cancel_timer(state.timer)

    :ok
  end

  @impl GenServer
  def handle_info(:prune, %State{} = state) do
    meta = %{conf: state.conf, plugin: __MODULE__}

    :telemetry.span([:oban, :plugin], meta, fn ->
      case check_leadership_and_delete_jobs(state) do
        {:ok, extra} when is_map(extra) ->
          {:ok, Map.merge(meta, extra)}

        error ->
          {:error, Map.put(meta, :error, error)}
      end
    end)

    {:noreply, schedule_prune(state)}
  end

  # Scheduling

  defp check_leadership_and_delete_jobs(state) do
    if Peer.leader?(state.conf) do
      Repo.transaction(state.conf, fn ->
        delete_jobs(state.conf, state.max_age, state.limit)
      end)
    else
      {:ok, %{}}
    end
  end

  defp schedule_prune(state) do
    %{state | timer: Process.send_after(self(), :prune, state.interval)}
  end

  # Query

  defp delete_jobs(conf, seconds, limit) do
    time = DateTime.add(DateTime.utc_now(), -seconds)

    subquery =
      Job
      |> or_where([j], j.state == "completed" and type(j.attempted_at, :utc_datetime) < ^time)
      |> or_where([j], j.state == "cancelled" and type(j.cancelled_at, :utc_datetime) < ^time)
      |> or_where([j], j.state == "discarded" and type(j.discarded_at, :utc_datetime) < ^time)
      |> limit(^limit)
      |> lock("FOR UPDATE SKIP LOCKED")

    query =
      Job
      |> join(:inner, [j], x in subquery(subquery), on: j.id == x.id)
      |> select([_, x], map(x, [:id, :queue, :state, :worker]))

    {pruned_count, pruned} = Repo.delete_all(conf, query)

    %{pruned_count: pruned_count, pruned_jobs: pruned}
  end
end
