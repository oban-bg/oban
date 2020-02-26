defmodule Oban.Queue.Producer do
  @moduledoc false

  use GenServer

  import Oban.Breaker, only: [open_circuit: 1, trip_errors: 0, trip_circuit: 3]
  import Oban.Notifier, only: [insert: 0, signal: 0]

  alias Oban.{Breaker, Config, Notifier, Query}
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
      :poll_ref,
      :rescue_ref,
      :started_at,
      circuit: :enabled,
      paused: false,
      running: %{}
    ]
  end

  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  @spec pause(GenServer.name()) :: :ok
  def pause(producer) do
    GenServer.call(producer, :pause)
  end

  @unlimited 100_000_000
  @far_future DateTime.from_unix!(9_999_999_999)

  @type drain_option :: {:with_scheduled, boolean()}

  @spec drain(queue :: binary(), config :: Config.t(), opts :: [drain_option()]) :: %{
          success: non_neg_integer(),
          failure: non_neg_integer()
        }
  def drain(queue, %Config{} = conf, opts \\ []) when is_binary(queue) and is_list(opts) do
    if Keyword.get(opts, :with_scheduled, false) do
      Query.stage_scheduled_jobs(conf, queue, max_scheduled_at: @far_future)
    end

    conf
    |> fetch_jobs(queue, nonce(), @unlimited)
    |> Enum.reduce(%{failure: 0, success: 0}, fn job, acc ->
      result = Executor.call(job, conf)

      Map.update(acc, result, 1, &(&1 + 1))
    end)
  end

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
    state
    |> rescue_orphans()
    |> start_listener()
    |> send_poll_after()
    |> send_rescue_after()
    |> dispatch()
  end

  @impl GenServer
  def terminate(_reason, %State{poll_ref: poll_ref, rescue_ref: rescue_ref}) do
    if is_reference(poll_ref), do: Process.cancel_timer(poll_ref)
    if is_reference(rescue_ref), do: Process.cancel_timer(rescue_ref)

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
    %State{conf: conf, foreman: foreman, running: running} = state

    {{job, _pid}, running} = Map.pop(running, ref)

    # Without this we may crash the producer if there are any db errors. Alternatively, we would
    # block the producer while awaiting a retry.
    Task.Supervisor.async_nolink(foreman, fn ->
      Breaker.with_retry(fn ->
        Executor.report_failure(conf, job, 0, :error, reason, stack)
      end)
    end)

    dispatch(%{state | running: running})
  end

  def handle_info(:dispatch, %State{} = state) do
    dispatch(state)
  end

  def handle_info({:notification, insert(), payload}, %State{queue: queue} = state) do
    case payload do
      %{"queue" => ^queue} -> dispatch(state)
      _ -> {:noreply, state}
    end
  end

  def handle_info({:notification, signal(), payload}, state) do
    %State{conf: conf, foreman: foreman, queue: queue, running: running} = state

    state =
      case payload do
        %{"action" => "pause", "queue" => ^queue} ->
          %{state | paused: true}

        %{"action" => "resume", "queue" => ^queue} ->
          %{state | paused: false}

        %{"action" => "scale", "queue" => ^queue, "scale" => scale} ->
          %{state | limit: scale}

        %{"action" => "pkill", "job_id" => kid} ->
          for {_ref, {job, pid}} <- running, job.id == kid do
            with :ok <- DynamicSupervisor.terminate_child(foreman, pid) do
              Query.discard_job(conf, job)
            end
          end

          state

        _ ->
          state
      end

    dispatch(state)
  end

  def handle_info(:poll, %State{conf: conf} = state) do
    conf.repo.checkout(fn ->
      state
      |> deschedule()
      |> pulse()
      |> send_poll_after()
      |> dispatch()
    end)
  end

  def handle_info(:rescue, %State{conf: conf} = state) do
    conf.repo.checkout(fn ->
      state
      |> rescue_orphans()
      |> send_rescue_after()
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

  defp rescue_orphans(%State{conf: conf, queue: queue} = state) do
    Query.rescue_orphaned_jobs(conf, queue)

    state
  rescue
    exception in trip_errors() -> trip_circuit(exception, __STACKTRACE__, state)
  end

  defp start_listener(%State{conf: conf} = state) do
    conf.name
    |> Module.concat("Notifier")
    |> Notifier.listen([:insert, :signal])

    state
  end

  defp send_poll_after(%State{conf: conf} = state) do
    ref = Process.send_after(self(), :poll, conf.poll_interval)

    %{state | poll_ref: ref}
  end

  defp send_rescue_after(%State{conf: conf} = state) do
    ref = Process.send_after(self(), :rescue, conf.rescue_interval)

    %{state | rescue_ref: ref}
  end

  # Dispatching

  defp deschedule(%State{circuit: :disabled} = state) do
    state
  end

  defp deschedule(%State{conf: conf, queue: queue} = state) do
    Query.stage_scheduled_jobs(conf, queue)

    state
  rescue
    exception in trip_errors() -> trip_circuit(exception, __STACKTRACE__, state)
  end

  defp pulse(%State{circuit: :disabled} = state) do
    state
  end

  defp pulse(%State{conf: conf, running: running} = state) do
    running_ids = for {_ref, {%_{id: id}, _pid}} <- running, do: id

    args =
      state
      |> Map.take([:limit, :nonce, :paused, :queue, :started_at])
      |> Map.put(:node, conf.node)
      |> Map.put(:running, running_ids)

    Query.insert_beat(conf, args)

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
          conf
          |> fetch_jobs(queue, nonce, limit - map_size(running))
          |> start_jobs(state)
          |> Map.merge(running)

        {:noreply, %{state | cooldown_ref: nil, dispatched_at: system_now(), running: running}}

      cooldown_available?(state) ->
        %State{conf: conf, dispatched_at: dispatched_at} = state

        dispatch_after = system_now() - dispatched_at + conf.dispatch_cooldown
        cooldown_ref = Process.send_after(self(), :dispatch, dispatch_after)

        {:noreply, %{state | cooldown_ref: cooldown_ref}}

      true ->
        {:noreply, state}
    end
  rescue
    exception in trip_errors() -> {:noreply, trip_circuit(exception, __STACKTRACE__, state)}
  end

  defp dispatch_now?(%State{dispatched_at: nil}), do: true

  defp dispatch_now?(%State{conf: conf, dispatched_at: dispatched_at}) do
    system_now() > dispatched_at + conf.dispatch_cooldown
  end

  defp cooldown_available?(%State{cooldown_ref: ref}), do: is_nil(ref)

  defp fetch_jobs(conf, queue, nonce, count) do
    case Query.fetch_available_jobs(conf, queue, nonce, count) do
      {0, nil} -> []
      {_count, jobs} -> jobs
    end
  end

  defp start_jobs(jobs, %State{conf: conf, foreman: foreman}) do
    for job <- jobs, into: %{} do
      %{pid: pid, ref: ref} = Task.Supervisor.async_nolink(foreman, Executor, :call, [job, conf])

      {ref, {job, pid}}
    end
  end

  defp system_now, do: System.monotonic_time(:millisecond)
end
