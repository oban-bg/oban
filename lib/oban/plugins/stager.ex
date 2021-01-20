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

    :telemetry.span([:oban, :plugin], start_metadata, fn ->
      case lock_and_schedule_jobs(state) do
        {:ok, staged_count} when is_integer(staged_count) ->
          {:ok, Map.put(start_metadata, :staged_count, staged_count)}

        {:ok, false} ->
          {:ok, Map.put(start_metadata, :staged_count, 0)}

        error ->
          {:error, Map.put(start_metadata, :error, error)}
      end
    end)

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
