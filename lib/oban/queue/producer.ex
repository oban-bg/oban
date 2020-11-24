defmodule Oban.Queue.Producer do
  @moduledoc false

  use GenServer

  import Oban.Breaker, only: [open_circuit: 1, trip_errors: 0, trip_circuit: 3]

  alias Oban.{Breaker, Config, Notifier, Query, Registry, Repo, Telemetry}
  alias Oban.Queue.Executor

  @type option ::
          {:name, module()}
          | {:conf, Config.t()}
          | {:foreman, GenServer.name()}
          | {:limit, pos_integer()}
          | {:queue, binary()}

  defmodule State do
    @moduledoc false

    @enforce_keys [:conf, :foreman, :limit, :nonce, :queue]
    defstruct [
      :conf,
      :cooldown_ref,
      :dispatched_at,
      :foreman,
      :limit,
      :name,
      :nonce,
      :queue,
      :reset_timer,
      :started_at,
      :timer,
      circuit: :enabled,
      dispatch_cooldown: 5,
      paused: false,
      poll_interval: :timer.seconds(1),
      running: %{}
    ]
  end

  @spec start_link([option()]) :: GenServer.on_start()
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

    opts =
      opts
      |> Keyword.put(:nonce, nonce())
      |> Keyword.put(:started_at, DateTime.utc_now())

    {:ok, struct!(State, opts), {:continue, :start}}
  end

  @impl GenServer
  def handle_continue(:start, state) do
    state =
      state
      |> start_listener()
      |> schedule_poll()

    {:noreply, state}
  end

  @impl GenServer
  def terminate(_reason, %State{timer: timer}) do
    if is_reference(timer), do: Process.cancel_timer(timer)

    :ok
  end

  @impl GenServer
  def handle_info({ref, _val}, %State{running: running} = state) do
    Process.demonitor(ref, [:flush])

    dispatch(%{state | running: Map.delete(running, ref)})
  end

  def handle_info({:DOWN, ref, :process, _pid, :shutdown}, %State{running: running} = state) do
    Process.demonitor(ref, [:flush])

    dispatch(%{state | running: Map.delete(running, ref)})
  end

  # This message is only received when the job's task doesn't exit cleanly. This should be rare,
  # but it can happen when nested processes crash.
  def handle_info({:DOWN, ref, :process, _pid, {reason, stack}}, %State{} = state) do
    %State{foreman: foreman, running: running} = state

    {{exec, _pid}, running} = Map.pop(running, ref)

    # Without this we may crash the producer if there are any db errors. Alternatively, we would
    # block the producer while awaiting a retry.
    Task.Supervisor.async_nolink(foreman, fn ->
      Breaker.with_retry(fn ->
        %{exec | kind: :error, error: reason, stacktrace: stack, state: :failure}
        |> Executor.record_finished()
        |> Executor.report_finished()
      end)
    end)

    dispatch(%{state | running: running})
  end

  def handle_info(:dispatch, %State{} = state) do
    dispatch(state)
  end

  def handle_info({:notification, :insert, payload}, %State{queue: queue} = state) do
    case payload do
      %{"queue" => ^queue} -> dispatch(state)
      _ -> {:noreply, state}
    end
  end

  def handle_info({:notification, :signal, payload}, %State{queue: queue} = state) do
    state =
      case payload do
        %{"action" => "pause", "queue" => ^queue} ->
          %{state | paused: true}

        %{"action" => "resume", "queue" => ^queue} ->
          %{state | paused: false}

        %{"action" => "scale", "queue" => ^queue, "limit" => limit} ->
          %{state | limit: limit}

        %{"action" => "pkill", "job_id" => jid} ->
          for {ref, {exec, pid}} <- state.running, exec.job.id == jid do
            pkill(ref, exec.job, pid, state)
          end

          state

        _ ->
          state
      end

    dispatch(state)
  end

  def handle_info(:poll, %State{conf: conf} = state) do
    Repo.checkout(conf, fn ->
      state
      |> schedule_poll()
      |> deschedule()
      |> dispatch()
    end)
  end

  def handle_info(:reset_circuit, state) do
    {:noreply, open_circuit(state)}
  end

  def handle_info(_message, state) do
    {:noreply, state}
  end

  @impl GenServer
  def handle_call(:check, _from, %State{conf: conf, running: running} = state) do
    running_ids = for {_ref, {exec, _pid}} <- running, do: exec.job.id

    args =
      state
      |> Map.take([:limit, :nonce, :paused, :queue, :started_at])
      |> Map.put(:node, conf.node)
      |> Map.put(:running, running_ids)

    {:reply, args, state}
  end

  def handle_call(:pause, _from, state) do
    {:reply, :ok, %{state | paused: true}}
  end

  # Start Handlers

  defp nonce(size \\ 8) when size > 0 do
    size
    |> :crypto.strong_rand_bytes()
    |> Base.hex_encode32(case: :lower)
    |> String.slice(0..(size - 1))
  end

  defp start_listener(%State{conf: conf} = state) do
    conf.name
    |> Registry.whereis(Notifier)
    |> Notifier.listen([:insert, :signal])

    state
  end

  defp schedule_poll(%State{conf: conf} = state) do
    %{state | timer: Process.send_after(self(), :poll, conf.poll_interval)}
  end

  # Killing

  defp pkill(ref, job, pid, state) do
    %State{conf: conf, foreman: foreman, running: running} = state

    case DynamicSupervisor.terminate_child(foreman, pid) do
      :ok ->
        Query.cancel_job(conf, job)

        state

      {:error, :not_found} ->
        Process.demonitor(ref, [:flush])

        %{state | running: Map.delete(running, ref)}
    end
  end

  # Dispatching

  defp deschedule(%State{circuit: :disabled} = state) do
    state
  end

  defp deschedule(%State{conf: conf, queue: queue} = state) do
    Telemetry.span(
      :producer,
      fn -> Query.stage_scheduled_jobs(conf, queue) end,
      %{action: :deschedule, queue: queue}
    )

    state
  rescue
    exception in trip_errors() -> trip_circuit(exception, __STACKTRACE__, state)
  end

  defp dispatch(%State{paused: true} = state) do
    {:noreply, state}
  end

  defp dispatch(%State{circuit: :disabled} = state) do
    {:noreply, state}
  end

  defp dispatch(%State{limit: limit, running: running} = state) when map_size(running) >= limit do
    {:noreply, state}
  end

  defp dispatch(%State{} = state) do
    cond do
      dispatch_now?(state) ->
        %State{conf: conf, limit: limit, nonce: nonce, queue: queue, running: running} = state

        running =
          Telemetry.span(
            :producer,
            fn ->
              conf
              |> fetch_jobs(queue, nonce, limit - map_size(running))
              |> start_jobs(state)
              |> Map.merge(running)
            end,
            %{action: :dispatch, queue: queue}
          )

        {:noreply, %{state | cooldown_ref: nil, dispatched_at: system_now(), running: running}}

      cooldown_available?(state) ->
        dispatch_after = system_now() - state.dispatched_at + state.dispatch_cooldown
        cooldown_ref = Process.send_after(self(), :dispatch, dispatch_after)

        {:noreply, %{state | cooldown_ref: cooldown_ref}}

      true ->
        {:noreply, state}
    end
  rescue
    exception in trip_errors() -> {:noreply, trip_circuit(exception, __STACKTRACE__, state)}
  end

  defp dispatch_now?(%State{dispatched_at: nil}), do: true

  defp dispatch_now?(%State{} = state) do
    system_now() > state.dispatched_at + state.dispatch_cooldown
  end

  defp cooldown_available?(%State{cooldown_ref: ref}), do: is_nil(ref)

  defp fetch_jobs(conf, queue, nonce, count) do
    {:ok, jobs} = Query.fetch_available_jobs(conf, queue, nonce, count)

    jobs
  end

  defp start_jobs(jobs, %State{conf: conf, foreman: foreman}) do
    for job <- jobs, into: %{} do
      exec = Executor.new(conf, job)

      %{pid: pid, ref: ref} = Task.Supervisor.async_nolink(foreman, Executor, :call, [exec])

      {ref, {exec, pid}}
    end
  end

  defp system_now, do: System.monotonic_time(:millisecond)
end
