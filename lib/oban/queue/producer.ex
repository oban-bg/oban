defmodule Oban.Queue.Producer do
  @moduledoc false

  use GenServer

  alias Oban.{Backoff, Engine, Notifier, PerformError, TimeoutError, Worker}
  alias Oban.Queue.Executor
  alias __MODULE__, as: State

  defstruct [
    :conf,
    :foreman,
    :meta,
    :name,
    :dispatch_timer,
    :refresh_timer,
    dispatch_cooldown: 5,
    running: %{}
  ]

  @spec start_link([Keyword.t()]) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  @spec check(GenServer.name()) :: Oban.queue_state()
  def check(producer) do
    GenServer.call(producer, :check)
  end

  @spec shutdown(GenServer.name()) :: :ok
  def shutdown(producer) do
    GenServer.call(producer, :shutdown)
  end

  # Callbacks

  @impl GenServer
  def init(opts) do
    Process.flag(:trap_exit, true)

    {base_opts, meta_opts} = Keyword.split(opts, [:conf, :foreman, :name, :dispatch_cooldown])

    state = struct!(State, base_opts)

    {:ok, state, {:continue, {:start, meta_opts}}}
  end

  @impl GenServer
  def terminate(_reason, %State{} = state) do
    if is_reference(state.refresh_timer), do: Process.cancel_timer(state.refresh_timer)
    if is_reference(state.dispatch_timer), do: Process.cancel_timer(state.dispatch_timer)

    :ok
  end

  @impl GenServer
  def handle_continue({:start, meta_opts}, %State{} = state) do
    {:ok, meta} = Engine.init(state.conf, meta_opts)

    :ok = Notifier.listen(state.conf.name, [:insert, :signal])

    {:noreply, schedule_refresh(%{state | meta: meta})}
  end

  @impl GenServer
  def handle_info({ref, _val}, %State{} = state) when is_reference(ref) do
    state =
      state
      |> release_ref(ref)
      |> schedule_dispatch()

    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, pid, reason}, %State{} = state) do
    {^pid, exec} = Map.get(state.running, ref)

    # The worker module is resolved after storing the exec struct. We try to resolve it again in
    # order to get a worker's custom `backoff/1`.
    exec =
      case Worker.from_string(exec.job.worker) do
        {:ok, worker} -> %{exec | worker: worker}
        {:error, _error} -> exec
      end

    exec =
      case reason do
        %TimeoutError{} ->
          %{exec | kind: :error, error: reason, state: :failure}

        :shutdown ->
          result = {:cancel, :shutdown}
          reason = PerformError.exception({exec.job.worker, result})

          %{exec | result: result, error: reason, state: :cancelled}

        {error, stack} ->
          %{exec | kind: {:EXIT, pid}, error: error, stacktrace: stack, state: :failure}

        _ ->
          %{exec | kind: {:EXIT, pid}, error: reason, state: :failure}
      end

    Task.Supervisor.async_nolink(state.foreman, fn ->
      exec =
        exec
        |> Executor.normalize_state()
        |> Executor.record_finished()
        |> Executor.cancel_timeout()

      Backoff.with_retry(fn -> Executor.report_finished(exec) end)
    end)

    state =
      state
      |> release_ref(ref)
      |> schedule_dispatch()

    {:noreply, state}
  end

  def handle_info({:notification, :insert, %{"queue" => queue}}, %State{} = state) do
    state = if state.meta.queue == queue, do: schedule_dispatch(state), else: state

    {:noreply, state}
  end

  def handle_info({:notification, :signal, payload}, %State{} = state) do
    queue = state.meta.queue

    meta =
      case payload do
        %{"action" => "pause", "queue" => "*"} ->
          Engine.put_meta(state.conf, state.meta, :paused, true)

        %{"action" => "resume", "queue" => "*"} ->
          Engine.put_meta(state.conf, state.meta, :paused, false)

        %{"action" => "pause", "queue" => ^queue} ->
          Engine.put_meta(state.conf, state.meta, :paused, true)

        %{"action" => "resume", "queue" => ^queue} ->
          Engine.put_meta(state.conf, state.meta, :paused, false)

        %{"action" => "scale", "queue" => ^queue} ->
          payload
          |> Map.drop(["action", "ident", "queue"])
          |> Enum.reduce(state.meta, fn {key, val}, meta ->
            Engine.put_meta(state.conf, meta, String.to_existing_atom(key), val)
          end)

        %{"action" => "pkill", "job_id" => jid} ->
          for {ref, {pid, exec}} <- state.running, exec.job.id == jid do
            pkill(ref, pid, state)
          end

          state.meta

        _ ->
          state.meta
      end

    {:noreply, schedule_dispatch(%{state | meta: meta})}
  end

  def handle_info(:dispatch, %State{} = state) do
    {:noreply, dispatch(%{state | dispatch_timer: nil})}
  end

  def handle_info(:refresh, %State{} = state) do
    meta = Engine.refresh(state.conf, state.meta)

    {:noreply, schedule_refresh(%{state | meta: meta})}
  end

  def handle_info(_message, state) do
    {:noreply, state}
  end

  @impl GenServer
  def handle_call(:check, _from, %State{} = state) do
    meta = Engine.check_meta(state.conf, state.meta, state.running)

    {:reply, meta, state}
  end

  def handle_call({:put_meta, key, value}, _from, %State{} = state) do
    meta = Engine.put_meta(state.conf, state.meta, key, value)

    {:reply, meta, %{state | meta: meta}}
  end

  def handle_call(:shutdown, _from, %State{} = state) do
    meta = Engine.shutdown(state.conf, state.meta)

    {:reply, :ok, %{state | meta: meta}}
  end

  # Killing

  defp pkill(ref, pid, %State{} = state) do
    case Task.Supervisor.terminate_child(state.foreman, pid) do
      :ok ->
        state

      {:error, :not_found} ->
        release_ref(state, ref)
    end
  end

  # Dispatching

  defp schedule_dispatch(%State{} = state) do
    if is_reference(state.dispatch_timer) do
      state
    else
      timer = Process.send_after(self(), :dispatch, state.dispatch_cooldown)

      %{state | dispatch_timer: timer}
    end
  end

  defp schedule_refresh(%State{} = state) do
    cooldown = Backoff.jitter(state.meta.refresh_interval, mode: :dec, mult: 0.5)
    timer = Process.send_after(self(), :refresh, cooldown)

    %{state | refresh_timer: timer}
  end

  defp dispatch(%State{} = state) do
    tele_meta = %{conf: state.conf, queue: state.meta.queue}

    {meta, dispatched} =
      :telemetry.span([:oban, :producer], tele_meta, fn ->
        {meta, dispatched} = start_jobs(state)

        {{meta, dispatched}, Map.put(tele_meta, :dispatched_count, map_size(dispatched))}
      end)

    %{state | meta: meta, running: Map.merge(state.running, dispatched)}
  end

  defp start_jobs(%State{} = state) do
    {:ok, {meta, jobs}} = Engine.fetch_jobs(state.conf, state.meta, state.running)

    dispatched =
      for job <- jobs, into: %{} do
        exec = Executor.new(state.conf, job)
        task = Task.Supervisor.async_nolink(state.foreman, Executor, :call, [exec])

        {task.ref, {task.pid, exec}}
      end

    {meta, dispatched}
  end

  defp release_ref(%State{} = state, ref) do
    Process.demonitor(ref, [:flush])

    %{state | running: Map.delete(state.running, ref)}
  end
end
