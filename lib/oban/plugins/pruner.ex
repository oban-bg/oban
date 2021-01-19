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

  ## Options

  * `:max_age` — the number of seconds after which a job may be pruned
  * `:limit` — the maximum number of jobs to prune at one time. The default is 10,000 to prevent
    request timeouts. Applications that steadily generate more than 10k jobs a minute should increase
    this value.

  ## Instrumenting with Telemetry

  Given that all the Oban plugins emit telemetry events under the `[:oban, :plugin, *]` pattern,
  you can filter out for `Pruner` specific events by filtering for telemetry events with a metadata
  key/value of `plugin: Oban.Plugins.Pruner`. Oban emits the following telemetry event whenever the
  `Pruner` plugin executes.

  * `[:oban, :plugin, :start]` — at the point that the `Pruner` plugin begins evaluating what old jobs to prune
  * `[:oban, :plugin, :stop]` — after the `Pruner` plugin has deleted any old jobs
  * `[:oban, :plugin, :exception]` — after the `Pruner` plugin fails to delete old jobs

  The following chart shows which metadata you can expect for each event:

  | event        | measures       | metadata                                       |
  | ------------ | ---------------| -----------------------------------------------|
  | `:start`     | `:system_time` | `:config, :plugin`                             |
  | `:stop`      | `:duration`    | `:pruned_count, :config, :plugin`         |
  | `:exception` | `:duration`    | `:error, :kind, :stacktrace, :config, :plugin` |
  """

  use GenServer

  import Ecto.Query

  alias Oban.{Config, Job, Query, Repo}

  @type option ::
          {:conf, Config.t()}
          | {:name, GenServer.name()}
          | {:limit, pos_integer()}
          | {:max_age, pos_integer()}

  defmodule State do
    @moduledoc false

    defstruct [
      :conf,
      :name,
      :timer,
      max_age: 60,
      interval: :timer.seconds(30),
      limit: 10_000,
      lock_key: 1_149_979_440_242_868_002
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
      |> schedule_prune()

    {:ok, state}
  end

  @impl GenServer
  def terminate(_reason, state) do
    if is_reference(state.timer), do: Process.cancel_timer(state.timer)

    :ok
  end

  @impl GenServer
  def handle_info(:prune, %State{} = state) do
    start_metadata = %{config: state.conf, plugin: __MODULE__}

    :telemetry.span(
      [:oban, :plugin],
      start_metadata,
      fn ->
        case lock_and_delete_jobs(state) do
          {:ok, {pruned_count, _}} ->
            {:ok, Map.put(start_metadata, :pruned_count, pruned_count)}

          false ->
            {:ok, Map.put(start_metadata, :pruned_count, 0)}

          error ->
            {:error, Map.put(start_metadata, :error, error)}
        end
      end
    )

    {:noreply, schedule_prune(state)}
  end

  # Scheduling

  defp lock_and_delete_jobs(state) do
    Query.with_xact_lock(state.conf, state.lock_key, fn ->
      delete_jobs(state.conf, state.max_age, state.limit)
    end)
  end

  defp schedule_prune(state) do
    %{state | timer: Process.send_after(self(), :prune, state.interval)}
  end

  # Query

  defp delete_jobs(conf, seconds, limit) do
    outdated_at = DateTime.add(DateTime.utc_now(), -seconds)

    subquery =
      Job
      |> where([j], j.state in ["completed", "cancelled", "discarded"])
      |> where([j], j.attempted_at < ^outdated_at)
      |> select([:id])
      |> limit(^limit)

    Repo.delete_all(
      conf,
      join(Job, :inner, [j], x in subquery(subquery), on: j.id == x.id)
    )
  end
end
