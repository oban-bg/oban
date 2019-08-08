defmodule Oban.Queue.Producer do
  @moduledoc false

  use GenServer

  require Logger

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
    defstruct [
      :conf,
      :foreman,
      :limit,
      :queue,
      circuit: :enabled,
      circuit_backoff: :timer.minutes(1),
      poll_ref: nil,
      running: %{},
      paused: false
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
    |> fetch_jobs(queue, @unlimited)
    |> Enum.reduce(%{failure: 0, success: 0}, fn job, acc ->
      result = Executor.call(job, conf)

      Map.update(acc, result, 1, &(&1 + 1))
    end)
  end

  @impl GenServer
  def init(opts) do
    Process.flag(:trap_exit, true)

    {:ok, struct!(State, opts), {:continue, :start}}
  end

  @impl GenServer
  def handle_continue(:start, state) do
    state
    |> rescue_orphans()
    |> start_listener()
    |> send_after()
    |> dispatch()
  end

  @impl GenServer
  def terminate(_reason, %State{poll_ref: poll_ref}) do
    # There is a good chance that a message will be received after the process has terminated.
    # While this doesn't cause any problems, it does cause an unwanted crash report.
    if not is_nil(poll_ref), do: Process.cancel_timer(poll_ref)

    :ok
  end

  @impl GenServer
  def handle_info(:poll, state) do
    state
    |> deschedule()
    |> gossip()
    |> send_after()
    |> dispatch()
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %State{running: running} = state) do
    dispatch(%{state | running: Map.delete(running, ref)})
  end

  def handle_info({:notification, _, _, prefixed_channel, payload}, state) do
    [_prefix, channel] = String.split(prefixed_channel, ".")

    handle_notification(channel, payload, state)
  end

  def handle_info(:reset_circuit, state) do
    {:noreply, %{state | circuit: :enabled}}
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
    Query.rescue_orphaned_jobs(conf, queue)

    state
  rescue
    exception in [Postgrex.Error] -> trip_circuit(exception, state)
  end

  defp start_listener(%State{conf: conf} = state) do
    notifier = Module.concat(conf.name, "Notifier")

    :ok = Notifier.listen(notifier, conf.prefix, :insert)
    :ok = Notifier.listen(notifier, conf.prefix, :signal)

    state
  end

  defp send_after(%State{conf: conf} = state) do
    poll_ref = Process.send_after(self(), :poll, conf.poll_interval)

    %{state | poll_ref: poll_ref}
  end

  # Notifications

  defp handle_notification(insert(), payload, %State{queue: queue} = state) do
    case Jason.decode(payload) do
      {:ok, %{"queue" => ^queue}} -> dispatch(state)
      _ -> {:noreply, state}
    end
  end

  defp handle_notification(signal(), payload, state) do
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
              Query.discard_job(conf, job)
            end
          end

          state

        {:ok, _} ->
          state
      end

    dispatch(state)
  end

  # Dispatching

  defp deschedule(%State{circuit: :disabled} = state) do
    state
  end

  defp deschedule(%State{conf: conf, queue: queue} = state) do
    Query.stage_scheduled_jobs(conf, queue)

    state
  rescue
    exception in [Postgrex.Error] -> trip_circuit(exception, state)
  end

  defp gossip(%State{circuit: :disabled} = state) do
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

    :ok = Query.notify(conf, Notifier.gossip(), Jason.encode!(message))

    state
  rescue
    exception in [Postgrex.Error] -> trip_circuit(exception, state)
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
    %State{queue: queue, limit: limit, running: running} = state

    started_jobs =
      for job <- fetch_jobs(conf, queue, limit - map_size(running)), into: %{} do
        {:ok, pid} = DynamicSupervisor.start_child(foreman, Executor.child_spec(job, conf))

        {Process.monitor(pid), {job, pid}}
      end

    {:noreply, %{state | running: Map.merge(running, started_jobs)}}
  rescue
    exception in [Postgrex.Error] -> {:noreply, trip_circuit(exception, state)}
  end

  defp fetch_jobs(conf, queue, count) do
    case Query.fetch_available_jobs(conf, queue, count) do
      {0, nil} -> []
      {_count, jobs} -> jobs
    end
  end

  # Circuit Breaker

  defp trip_circuit(exception, state) do
    Logger.error(fn ->
      Jason.encode!(%{
        source: "oban",
        message: "Circuit temporarily tripped by Postgrex.Error",
        error: Postgrex.Error.message(exception)
      })
    end)

    Process.send_after(self(), :reset_circuit, state.circuit_backoff)

    %{state | circuit: :disabled}
  end
end
