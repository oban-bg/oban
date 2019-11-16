defmodule Oban.Queue.Producer do
  @moduledoc false

  use GenServer

  import Oban.Breaker, only: [open_circuit: 1, trip_errors: 0, trip_circuit: 2]
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

    @enforce_keys [:conf, :foreman, :limit, :nonce, :queue]
    defstruct [
      :conf,
      :foreman,
      :limit,
      :nonce,
      :queue,
      :poll_ref,
      :rescue_ref,
      :started_at,
      circuit: :enabled,
      circuit_backoff: :timer.seconds(30),
      paused: false,
      running: %{}
    ]
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

  @unlimited 100_000_000

  @spec drain(queue :: binary(), config :: Config.t()) :: %{
          success: non_neg_integer(),
          failure: non_neg_integer()
        }
  def drain(queue, %Config{} = conf) when is_binary(queue) do
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
    # There is a good chance that a message will be received after the process has terminated.
    # While this doesn't cause any problems, it does cause an unwanted crash report.
    if not is_nil(poll_ref), do: Process.cancel_timer(poll_ref)
    if not is_nil(rescue_ref), do: Process.cancel_timer(rescue_ref)

    :ok
  end

  @impl GenServer
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

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %State{running: running} = state) do
    dispatch(%{state | running: Map.delete(running, ref)})
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
    exception in trip_errors() -> trip_circuit(exception, state)
  end

  defp start_listener(%State{conf: conf} = state) do
    conf.name
    |> Module.concat("Notifier")
    |> Notifier.listen()

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
    exception in trip_errors() -> trip_circuit(exception, state)
  end

  defp pulse(%State{circuit: :disabled} = state) do
    state
  end

  defp pulse(%State{conf: conf} = state) do
    args =
      state
      |> Map.take([:limit, :nonce, :paused, :queue, :started_at])
      |> Map.put(:node, conf.node)
      |> Map.put(:running, running_job_ids(state))

    Query.insert_beat(conf, args)

    state
  rescue
    exception in trip_errors() -> trip_circuit(exception, state)
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

  defp dispatch(%State{conf: conf, foreman: foreman} = state) do
    %State{limit: limit, nonce: nonce, queue: queue, running: running} = state

    started_jobs =
      for job <- fetch_jobs(conf, queue, nonce, limit - map_size(running)), into: %{} do
        {:ok, pid} = DynamicSupervisor.start_child(foreman, Executor.child_spec(job, conf))

        {Process.monitor(pid), {job, pid}}
      end

    {:noreply, %{state | running: Map.merge(running, started_jobs)}}
  rescue
    exception in trip_errors() -> {:noreply, trip_circuit(exception, state)}
  end

  defp fetch_jobs(conf, queue, nonce, count) do
    case Query.fetch_available_jobs(conf, queue, nonce, count) do
      {0, nil} -> []
      {_count, jobs} -> jobs
    end
  end

  defp running_job_ids(%State{running: running}) do
    for {_ref, {%_{id: id}, _pid}} <- running, do: id
  end
end
