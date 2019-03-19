defmodule Oban.Queue.Producer do
  @moduledoc false

  use GenServer

  alias Oban.{Config, Query}
  alias Oban.Queue.Executor

  @type option ::
          {:name, module()}
          | {:conf, Config.t()}
          | {:foreman, GenServer.name()}
          | {:limit, pos_integer()}
          | {:queue, binary()}

  defmodule State do
    @moduledoc false

    @enforce_keys [:conf, :foreman, :limit, :queue]
    defstruct [:conf, :queue, :foreman, :limit, running: 0, paused: false]
  end

  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)

    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec pause(GenServer.name()) :: :ok
  def pause(producer) do
    GenServer.call(producer, :pause)
  end

  @spec resume(GenServer.name()) :: :ok
  def resume(producer) do
    GenServer.call(producer, :resume)
  end

  @spec scale(GenServer.name(), pos_integer()) :: :ok
  def scale(producer, limit) do
    GenServer.call(producer, {:scale, limit})
  end

  @impl GenServer
  def init(opts) do
    %Config{poll_interval: interval} = Keyword.fetch!(opts, :conf)

    {:ok, _ref} = :timer.send_interval(interval, :poll)

    {:ok, struct!(State, opts), {:continue, :start}}
  end

  @impl GenServer
  def handle_continue(:start, %State{conf: conf, queue: queue} = state) do
    Query.rescue_orphaned_jobs(conf.repo, queue)

    dispatch(state)
  end

  @impl GenServer
  def handle_info(:poll, state) do
    dispatch(state)
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, %State{running: running} = state) do
    dispatch(%{state | running: running - 1})
  end

  @impl GenServer
  def handle_call(:pause, _from, state) do
    {:reply, :ok, %{state | paused: true}}
  end

  def handle_call(:resume, _from, state) do
    {:reply, :ok, %{state | paused: false}}
  end

  def handle_call({:scale, limit}, _from, state) do
    {:noreply, state} = dispatch(%{state | limit: limit})

    {:reply, :ok, state}
  end

  defp dispatch(%State{paused: true} = state) do
    {:noreply, state}
  end

  defp dispatch(%State{limit: limit, running: running} = state) when running >= limit do
    {:noreply, state}
  end

  defp dispatch(%State{conf: conf, foreman: foreman} = state) do
    %State{queue: queue, limit: limit, running: running} = state

    {count, jobs} =
      case Query.fetch_available_jobs(conf.repo, queue, limit - running) do
        {0, nil} -> {0, []}
        {count, jobs} -> {count, jobs}
      end

    for job <- jobs do
      {:ok, pid} = DynamicSupervisor.start_child(foreman, Executor.child_spec(job, conf))

      Process.monitor(pid)
    end

    {:noreply, %{state | running: running + count}}
  end
end
