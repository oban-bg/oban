defmodule Oban.Queue.Watchman do
  @moduledoc false

  use GenServer

  alias Oban.Queue.Producer
  alias __MODULE__, as: State

  defstruct [:conf, :producer, :shutdown, interval: 10]

  @spec child_spec(Keyword.t()) :: Supervisor.child_spec()
  def child_spec(opts) do
    shutdown = Keyword.fetch!(opts, :shutdown) + Keyword.get(opts, :interval, 10)

    %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}, shutdown: shutdown}
  end

  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)

    GenServer.start_link(__MODULE__, struct!(State, opts), name: name)
  end

  @impl GenServer
  def init(state) do
    Process.flag(:trap_exit, true)

    {:ok, state}
  end

  @impl GenServer
  def terminate(_reason, %State{} = state) do
    # The producer may not exist, and we don't want to raise during shutdown.
    :ok = Producer.shutdown(state.producer)
    :ok = wait_for_executing(0, state)
  catch
    :exit, _reason -> :ok
  end

  defp wait_for_executing(elapsed, state) do
    check = Producer.check(state.producer)

    if check.running == [] or elapsed >= state.shutdown do
      :telemetry.execute(
        [:oban, :queue, :shutdown],
        %{elapsed: elapsed, ellapsed: elapsed},
        %{conf: state.conf, orphaned: check.running, queue: check.queue}
      )

      :ok
    else
      :ok = Process.sleep(state.interval)

      wait_for_executing(elapsed + state.interval, state)
    end
  end
end
