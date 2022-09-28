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
  > `DynamicLifeline` plugin in [Oban Pro](https://getoban.pro/docs/pro/dynamic_lifeline.html).

  ## Using the Plugin

  Rescue orphaned jobs that are still `executing` after the default of 60 minutes:

      config :my_app, Oban,
        plugins: [Oban.Plugins.Lifeline],
        ...

  Override the default period to rescue orphans after a more aggressive period of 5 minutes:

      config :my_app, Oban,
        plugins: [{Oban.Plugins.Lifeline, rescue_after: :timer.minutes(5)}],
        ...

  If you want a more granular option, you can also override the default period
  to rescue specific Oban workers by their names:

      config :my_app, Oban,
        plugins: [{Oban.Plugins.Lifeline, worker_overrides: [{MyApp.MyWorker, :timer.minutes(5)}]],
        ...

  ## Options

  * `:interval` — the number of milliseconds between rescue attempts. The default is `60_000ms`.

  * `:rescue_after` — the maximum amount of time, in milliseconds, that a job may execute before
  being rescued. 60 minutes by default, and rescuing is performed once a minute.

  * :`:worker_overrides` - allows to override the maximum amount of time, in
  milliseconds, that an specific Oban Worker may execute before being
  rescued.

   * `:timeout` - time in milliseconds to wait for each query call to finish.
   Defaults to 15 seconds.

  ## Instrumenting with Telemetry

  The `Oban.Plugins.Lifeline` plugin adds the following metadata to the `[:oban, :plugin, :stop]`
  event:

  * `:rescued_count` — the number of jobs transitioned back to `available`
  * `:discarded_count` — the number of jobs transitioned to `discarded`
  """

  @behaviour Oban.Plugin

  use GenServer

  import Ecto.Query, only: [where: 3]

  alias Oban.{Job, Peer, Plugin, Repo, Validation}

  @type option ::
          Plugin.option()
          | {:interval, timeout()}
          | {:rescue_after, pos_integer()}

  defmodule State do
    @moduledoc false

    defstruct [
      :conf,
      :name,
      :timer,
      interval: :timer.minutes(1),
      rescue_after: :timer.minutes(60),
      worker_overrides: [],
      excluded_worker_names: [],
      timeout: :timer.seconds(15)
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
      {:rescue_after, interval} -> Validation.validate_integer(:rescue_after, interval)
      {:worker_overrides, overrides} -> validate_overrides(:worker_overrides, overrides)
      {:timeout, timeout} -> Validation.validate_timeout(:timeout, timeout)
      option -> {:error, "unknown option provided: #{inspect(option)}"}
    end)
  end

  @impl GenServer
  def init(opts) do
    Validation.validate!(opts, &validate/1)

    {excluded_worker_names, worker_overrides} = normalize_worker_overrides(opts)

    opts =
      Keyword.merge(opts,
        worker_overrides: worker_overrides,
        excluded_worker_names: excluded_worker_names
      )

    state =
      State
      |> struct!(opts)
      |> schedule_rescue()

    :telemetry.execute([:oban, :plugin, :init], %{}, %{conf: state.conf, plugin: __MODULE__})

    {:ok, state}
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
        {:ok, {rescued_count, discarded_count}} when is_integer(rescued_count) ->
          meta =
            meta
            |> Map.put(:rescued_count, rescued_count)
            |> Map.put(:discarded_count, discarded_count)

          {:ok, meta}

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
      Repo.transaction(
        state.conf,
        fn ->
          now = DateTime.utc_now()
          base = where(Job, [j], j.state == "executing")

          worker_counts =
            for {worker, rescue_after} <- state.worker_overrides do
              time = DateTime.add(now, -rescue_after, :millisecond)
              query = where(base, [j], j.attempted_at < ^time and j.worker == ^worker)
              run_transitions(query, state)
            end

          time = DateTime.add(now, -state.rescue_after, :millisecond)

          query =
            base
            |> where([j], j.attempted_at < ^time)
            |> exclude_workers(state.excluded_worker_names)

          default_counts = run_transitions(query, state)

          Enum.reduce(worker_counts, default_counts, fn {r, d}, {rescued_count, discard_count} ->
            {rescued_count + r, discard_count + d}
          end)
        end,
        timeout: state.timeout
      )
    else
      {:ok, 0, 0}
    end
  end

  defp run_transitions(query, state) do
    {rescued_count, _} = transition_available(query, state)
    {discard_count, _} = transition_discarded(query, state)

    {rescued_count, discard_count}
  end

  defp transition_available(query, state) do
    Repo.update_all(
      state.conf,
      where(query, [j], j.attempt < j.max_attempts),
      set: [state: "available"]
    )
  end

  defp transition_discarded(query, state) do
    Repo.update_all(state.conf, where(query, [j], j.attempt >= j.max_attempts),
      set: [state: "discarded", discarded_at: DateTime.utc_now()]
    )
  end

  defp validate_overrides(parent_key, overrides) do
    Validation.validate(parent_key, overrides, fn
      {worker, rescue_after} when is_atom(worker) and is_integer(rescue_after) ->
        Validation.validate_integer(:rescue_after, rescue_after)

      override ->
        {:error, "expected #{inspect(parent_key)} to contain a tuple, got: #{inspect(override)}"}
    end)
  end

  defp exclude_workers(queryable, []), do: queryable

  defp exclude_workers(queryable, excluded_worker_names),
    do: where(queryable, [j], j.worker not in ^excluded_worker_names)

  defp normalize_worker_overrides(opts) do
    opts
    |> Keyword.get(:worker_overrides, [])
    |> Enum.reduce({[], []}, fn {worker, rescue_after},
                                {excluded_worker_names, worker_overrides} ->
      worker_name = Oban.Worker.to_string(worker)

      {[worker_name | excluded_worker_names], [{worker_name, rescue_after} | worker_overrides]}
    end)
  end
end
