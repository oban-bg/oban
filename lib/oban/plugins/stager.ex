defmodule Oban.Plugins.Stager do
  @moduledoc """
  Transition jobs to the `available` state when they reach their scheduled time.

  This module is necessary for the execution of scheduled and retryable jobs.
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
      interval: :timer.seconds(1)
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

  # TODO: Wrap in an xact lock
  # TODO: Add telemetry span function
  #
  # Telemetry.span(
  #   :producer,
  #   fn -> Query.stage_scheduled_jobs(conf, queue) end,
  #   %{action: :deschedule, queue: queue, config: conf}
  # )

  @impl GenServer
  def handle_info(:stage, %State{conf: conf} = state) do
    with {:ok, [_ | _] = queues} <- Query.stage_scheduled_jobs(conf) do
      queues
      |> Enum.uniq()
      |> Enum.each(&Query.notify(conf, "oban_insert", %{queue: &1}))
    end

    {:noreply, state}
  end

  defp schedule_staging(state) do
    timer = Process.send_after(self(), :stage, state.interval)

    %{state | timer: timer}
  end
end
