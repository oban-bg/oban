defmodule Oban.Queue.Producer do
  @moduledoc false

  use GenServer

  alias Oban.{Breaker, Notifier}
  alias Oban.Queue.{Engine, Executor}

  defmodule State do
    @moduledoc false

    defstruct [
      :conf,
      :foreman,
      :meta,
      :name,
      :dispatch_timer,
      :refresh_timer,
      dispatch_cooldown: 5,
      refresh_interval: :timer.seconds(30),
      running: %{}
    ]
  end

  @spec start_link([Keyword.t()]) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  @spec check(GenServer.name()) :: Oban.queue_state()
  def check(producer) do
    GenServer.call(producer, :check)
  end

  @spec pause(GenServer.name()) :: :ok
  def pause(producer) do
    GenServer.call(producer, :pause)
  end

  # Callbacks

  @impl GenServer
  def init(opts) do
    Process.flag(:trap_exit, true)

    {base_opts, meta_opts} = Keyword.split(opts, [:conf, :foreman, :name, :dispatch_cooldown])

    state = struct!(State, base_opts)

    :ok = Notifier.listen(state.conf.name, [:insert, :signal])

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

  def handle_info({:DOWN, ref, :process, _pid, :shutdown}, %State{} = state) do
    state =
      state
      |> release_ref(ref)
      |> schedule_dispatch()

    {:noreply, state}
  end

  # This message is only received when the job's task doesn't exit cleanly. This should be rare,
  # but it can happen when nested processes crash.
  def handle_info({:DOWN, ref, :process, _pid, reason}, %State{} = state) do
    {_pid, exec} = Map.get(state.running, ref)

    {error, stack} =
      case reason do
        {error, stack} -> {error, stack}
        _ -> {reason, []}
      end

    # Without this we may crash the producer if there are any db errors. Alternatively, we would
    # block the producer while awaiting a retry.
    Task.Supervisor.async_nolink(state.foreman, fn ->
      Breaker.with_retry(fn ->
        %{exec | kind: :error, error: error, stacktrace: stack, state: :failure}
        |> Executor.record_finished()
        |> Executor.report_finished()
      end)
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
        %{"action" => "pause", "queue" => ^queue} ->
          Engine.put_meta(state.conf, state.meta, :paused, true)

        %{"action" => "resume", "queue" => ^queue} ->
          Engine.put_meta(state.conf, state.meta, :paused, false)

        %{"action" => "scale", "queue" => ^queue, "limit" => limit} ->
          Engine.put_meta(state.conf, state.meta, :limit, limit)

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

  def handle_call(:pause, _from, state) do
    meta = Engine.put_meta(state.conf, state.meta, :paused, true)

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
    cooldown = Breaker.jitter(state.refresh_interval, mode: :dec, mult: 0.5)
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
