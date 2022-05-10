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

  ## Options

  * `:interval` — the number of milliseconds between rescue attempts. The default is `60_000ms`.

  * `:rescue_after` — the maximum amount of time, in milliseconds, that a job may execute before
  being rescued. 60 minutes by default, and rescuing is performed once a minute.

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
      rescue_after: :timer.minutes(60)
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
      option -> {:error, "unknown option provided: #{inspect(option)}"}
    end)
  end

  @impl GenServer
  def init(opts) do
    Validation.validate!(opts, &validate/1)

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
      Repo.transaction(state.conf, fn ->
        time = DateTime.add(DateTime.utc_now(), -state.rescue_after, :millisecond)
        base = where(Job, [j], j.state == "executing" and j.attempted_at < ^time)

        {rescued_count, _} = transition_available(base, state)
        {discard_count, _} = transition_discarded(base, state)

        {rescued_count, discard_count}
      end)
    else
      {:ok, 0, 0}
    end
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
end
