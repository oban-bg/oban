defmodule Oban.Queue.Watchman do
  @moduledoc false

  use GenServer

  alias Oban.Queue.Producer
  alias __MODULE__, as: State

  defstruct [:conf, :producer, :queue, :shutdown, interval: 10]

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
    :ok = wait_for_drain(state)
  catch
    :exit, _reason -> :ok
  end

  defp wait_for_drain(%State{} = state) do
    receive do
      {:drained, _queue} -> emit_shutdown(0, [], state)
    after
      state.shutdown -> emit_shutdown(state.shutdown, orphaned(state), state)
    end

    :ok
  end

  defp orphaned(state) do
    Producer.check(state.producer).running
  catch
    :exit, _ -> []
  end

  defp emit_shutdown(elapsed, orphaned, %State{} = state) do
    :telemetry.execute(
      [:oban, :queue, :shutdown],
      %{elapsed: elapsed, ellapsed: elapsed},
      %{conf: state.conf, orphaned: orphaned, queue: state.queue}
    )
  end
end
