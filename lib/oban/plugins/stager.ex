defmodule Oban.Plugins.Stager do
  @moduledoc """
  Transition jobs to the `available` state when they reach their scheduled time.

  This module is necessary for the execution of scheduled and retryable jobs.

  ## Options

  * `:interval` - the number of milliseconds between database updates. This is directly tied to
    the resolution of _scheduled_ jobs. For example, with an `interval` of `5_000ms`, scheduled
    jobs are checked every 5 seconds. The default is `1_000ms`.

  ## Instrumenting with Telemetry

  Given that all the Oban plugins emit telemetry events under the `[:oban, :plugin, *]` pattern,
  you can filter out for `Stager` specific events by filtering for telemetry events with a metadata
  key/value of `plugin: Oban.Plugins.Stager`. Oban emits the following telemetry event whenever the
  `Stager` plugin executes.

  * `[:oban, :plugin, :start]` — at the point that the `Stager` plugin begins evaluating what jobs need to be staged
  * `[:oban, :plugin, :stop]` — after the `Stager` plugin has completed transition jobs to the available state
  * `[:oban, :plugin, :exception]` — after the `Stager` plugin fails to transition jobs to the available state

  The following chart shows which metadata you can expect for each event:

  | event        | measures       | metadata                                       |
  | ------------ | ---------------| -----------------------------------------------|
  | `:start`     | `:system_time` | `:config, :plugin`                             |
  | `:stop`      | `:duration`    | `:staged_count, :config, :plugin`         |
  | `:exception` | `:duration`    | `:error, :kind, :stacktrace, :config, :plugin` |
  """

  use GenServer

  alias Oban.{Config, Query}

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
    start_metadata = %{config: state.conf, plugin: __MODULE__}

    :telemetry.span(
      [:oban, :plugin],
      start_metadata,
      fn ->
        case lock_and_schedule_jobs(state) do
          {:ok, staged_count} ->
            {:ok, Map.put(start_metadata, :staged_count, staged_count)}

          error ->
            {:error, Map.put(start_metadata, :error, error)}
        end
      end
    )

    {:noreply, state}
  end

  defp lock_and_schedule_jobs(state) do
    Query.with_xact_lock(state.conf, state.lock_key, fn ->
      with {staged_count, [_ | _] = queues} <- Query.stage_scheduled_jobs(state.conf) do
        payloads =
          queues
          |> Enum.uniq()
          |> Enum.map(&%{queue: &1})

        Query.notify(state.conf, "oban_insert", payloads)

        staged_count
      end
    end)
  end

  defp schedule_staging(state) do
    timer = Process.send_after(self(), :stage, state.interval)

    %{state | timer: timer}
  end
end
