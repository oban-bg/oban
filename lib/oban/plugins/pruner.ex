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

  The `Oban.Plugins.Pruner` plugin adds the following metadata to the `[:oban, :plugin, :stop]` event:

  * :pruned_count - the number of jobs that were pruned from the database
  """

  use GenServer

  import Ecto.Query, only: [join: 5, limit: 2, select: 2, where: 3]

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
    meta = %{conf: state.conf, plugin: __MODULE__}

    :telemetry.span([:oban, :plugin], meta, fn ->
      case lock_and_delete_jobs(state) do
        {:ok, {pruned_count, _}} when is_integer(pruned_count) ->
          {:ok, Map.put(meta, :pruned_count, pruned_count)}

        {:ok, false} ->
          {:ok, Map.put(meta, :pruned_count, 0)}

        error ->
          {:error, Map.put(meta, :error, error)}
      end
    end)

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
