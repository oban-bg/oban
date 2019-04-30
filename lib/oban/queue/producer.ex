defmodule Oban.Queue.Producer do
  @moduledoc false

  use GenServer

  import Oban.Notifier, only: [insert: 0, signal: 0]

  alias Oban.{Config, Notifier, Query}
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
    defstruct [:conf, :foreman, :limit, :queue, running: %{}, paused: false]
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

  @impl GenServer
  def init(opts) do
    %Config{poll_interval: interval} = Keyword.fetch!(opts, :conf)

    {:ok, _ref} = :timer.send_interval(interval, :poll)

    {:ok, struct!(State, opts), {:continue, :start}}
  end

  @impl GenServer
  def handle_continue(:start, state) do
    state
    |> rescue_orphans()
    |> start_interval()
    |> start_listener()
    |> dispatch()
  end

  @impl GenServer
  def handle_info(:poll, state) do
    state
    |> deschedule()
    |> gossip()
    |> dispatch()
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %State{running: running} = state) do
    dispatch(%{state | running: Map.delete(running, ref)})
  end

  def handle_info({:notification, _, _, insert(), payload}, %State{queue: queue} = state) do
    case Jason.decode(payload) do
      {:ok, %{"queue" => ^queue}} -> dispatch(state)
      _ -> {:noreply, state}
    end
  end

  def handle_info({:notification, _, _, signal(), payload}, state) do
    %State{conf: conf, foreman: foreman, queue: queue, running: running} = state

    state =
      case Jason.decode(payload) do
        {:ok, %{"action" => "pause", "queue" => ^queue}} ->
          %{state | paused: true}

        {:ok, %{"action" => "resume", "queue" => ^queue}} ->
          %{state | paused: false}

        {:ok, %{"action" => "scale", "queue" => ^queue, "scale" => scale}} ->
          %{state | limit: scale}

        {:ok, %{"action" => "pkill", "job_id" => kid}} ->
          for {_ref, {job, pid}} <- running, job.id == kid do
            with :ok <- DynamicSupervisor.terminate_child(foreman, pid) do
              Query.discard_job(conf.repo, job)
            end
          end

          state

        {:ok, _} ->
          state
      end

    dispatch(state)
  end

  def handle_info(_message, state) do
    {:noreply, state}
  end

  @impl GenServer
  def handle_call(:pause, _from, state) do
    {:reply, :ok, %{state | paused: true}}
  end

  # Start Handlers

  defp rescue_orphans(%State{conf: conf, queue: queue} = state) do
    Query.rescue_orphaned_jobs(conf.repo, queue)

    state
  end

  defp start_interval(%State{conf: conf} = state) do
    {:ok, _ref} = :timer.send_interval(conf.poll_interval, :poll)

    state
  end

  defp start_listener(state) do
    :ok = Notifier.listen(:insert)
    :ok = Notifier.listen(:signal)

    state
  end

  # Dispatching

  defp deschedule(%State{conf: conf, queue: queue} = state) do
    Query.stage_scheduled_jobs(conf.repo, queue)

    state
  end

  defp gossip(state) do
    %State{conf: conf, limit: limit, paused: paused, queue: queue, running: running} = state

    message = %{
      count: map_size(running),
      limit: limit,
      node: conf.node,
      paused: paused,
      queue: queue
    }

    :ok = Notifier.notify(:gossip, message)

    state
  end

  defp dispatch(%State{paused: true} = state) do
    {:noreply, state}
  end

  defp dispatch(%State{limit: limit, running: running} = state) when map_size(running) >= limit do
    {:noreply, state}
  end

  defp dispatch(%State{conf: conf, foreman: foreman} = state) do
    %State{queue: queue, limit: limit, running: running} = state

    started_jobs =
      for job <- fetch_jobs(conf.repo, queue, limit - map_size(running)), into: %{} do
        {:ok, pid} = DynamicSupervisor.start_child(foreman, Executor.child_spec(job, conf))

        {Process.monitor(pid), {job, pid}}
      end

    {:noreply, %{state | running: Map.merge(running, started_jobs)}}
  end

  defp fetch_jobs(repo, queue, count) do
    case Query.fetch_available_jobs(repo, queue, count) do
      {0, nil} -> []
      {_count, jobs} -> jobs
    end
  end
end
