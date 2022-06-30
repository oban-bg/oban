defmodule Oban.Queue.Executor do
  @moduledoc false

  alias Oban.{Backoff, Config, CrashError, Engine, Job}
  alias Oban.{PerformError, Telemetry, TimeoutError, Worker}

  require Logger

  @type state :: :cancelled | :discard | :exhausted | :failure | :success | :snoozed

  @type t :: %__MODULE__{
          conf: Config.t(),
          duration: pos_integer(),
          job: Job.t(),
          kind: any(),
          meta: map(),
          queue_time: integer(),
          result: term(),
          start_mono: integer(),
          start_time: integer(),
          stop_mono: integer(),
          safe: boolean(),
          snooze: pos_integer(),
          stacktrace: Exception.stacktrace(),
          state: :unset | state(),
          timer: reference(),
          worker: Worker.t()
        }

  @type option :: {:ack, boolean()} | {:safe, boolean()}

  @enforce_keys [:conf, :job]
  defstruct [
    :ack,
    :conf,
    :error,
    :job,
    :meta,
    :result,
    :snooze,
    :start_mono,
    :start_time,
    :stop_mono,
    :timer,
    :worker,
    safe: true,
    duration: 0,
    kind: :error,
    queue_time: 0,
    stacktrace: [],
    state: :unset
  ]

  @spec new(Config.t(), Job.t(), [option()]) :: t()
  def new(%Config{} = conf, %Job{} = job, opts \\ []) do
    struct!(__MODULE__,
      ack: Keyword.get(opts, :ack, true),
      conf: conf,
      job: %{job | conf: conf},
      meta: event_metadata(conf, job),
      safe: Keyword.get(opts, :safe, true),
      start_mono: System.monotonic_time(),
      start_time: System.system_time()
    )
  end

  @spec call(t()) :: t()
  def call(%__MODULE__{} = exec) do
    exec =
      exec
      |> record_started()
      |> resolve_worker()
      |> start_timeout()
      |> perform()
      |> normalize_state()
      |> record_finished()
      |> cancel_timeout()

    complete = fn ->
      exec
      |> report_finished()
      |> reraise_unsafe()
    end

    if exec.safe do
      Backoff.with_retry(complete)
    else
      complete.()
    end
  end

  @spec record_started(t()) :: t()
  def record_started(%__MODULE__{} = exec) do
    Telemetry.execute([:oban, :job, :start], %{system_time: exec.start_time}, exec.meta)

    exec
  end

  @spec resolve_worker(t()) :: t()
  def resolve_worker(%__MODULE__{} = exec) do
    case Worker.from_string(exec.job.worker) do
      {:ok, worker} ->
        %{exec | worker: worker}

      {:error, error} ->
        unless exec.safe, do: raise(error)

        %{exec | state: :failure, error: error}
    end
  end

  @spec start_timeout(t()) :: t()
  def start_timeout(%__MODULE__{state: :unset} = exec) do
    case exec.worker.timeout(exec.job) do
      timeout when is_integer(timeout) ->
        {:ok, timer} = :timer.exit_after(timeout, TimeoutError.exception({exec.worker, timeout}))

        %{exec | timer: timer}

      :infinity ->
        exec
    end
  end

  def start_timeout(exec), do: exec

  @spec perform(t()) :: t()
  def perform(%__MODULE__{job: job, state: :unset, worker: worker} = exec) do
    case worker.perform(job) do
      :ok ->
        %{exec | state: :success, result: :ok}

      {:ok, _value} = result ->
        %{exec | state: :success, result: result}

      {:cancel, _reason} = result ->
        %{exec | result: result, state: :cancelled, error: perform_error(worker, result)}

      :discard = result ->
        %{exec | result: result, state: :discard, error: perform_error(worker, result)}

      {:discard, _reason} = result ->
        %{exec | result: result, state: :discard, error: perform_error(worker, result)}

      {:error, _reason} = result ->
        %{exec | result: result, state: :failure, error: perform_error(worker, result)}

      {:snooze, seconds} = result when is_integer(seconds) and seconds > 0 ->
        %{exec | result: result, state: :snoozed, snooze: seconds}

      returned ->
        log_warning(exec, returned)

        %{exec | state: :success, result: returned}
    end
  rescue
    error ->
      %{exec | state: :failure, error: error, stacktrace: __STACKTRACE__}
  catch
    kind, reason ->
      error = CrashError.exception({kind, reason, __STACKTRACE__})

      %{exec | state: :failure, error: error, stacktrace: __STACKTRACE__}
  end

  @spec normalize_state(t()) :: t()
  def normalize_state(%__MODULE__{state: :failure, job: job} = exec)
      when job.attempt >= job.max_attempts do
    %{exec | state: :exhausted}
  end

  def normalize_state(exec), do: exec

  @spec record_finished(t()) :: t()
  def record_finished(%__MODULE__{} = exec) do
    stop_mono = System.monotonic_time()
    duration = stop_mono - exec.start_mono
    queue_time = DateTime.diff(exec.job.attempted_at, exec.job.scheduled_at, :nanosecond)

    %{exec | duration: duration, queue_time: queue_time, stop_mono: stop_mono}
  end

  @spec cancel_timeout(t()) :: t()
  def cancel_timeout(%__MODULE__{timer: timer} = exec) do
    unless is_nil(timer), do: :timer.cancel(timer)

    exec
  end

  @spec reraise_unsafe(t()) :: t()
  def reraise_unsafe(%__MODULE__{safe: false, stacktrace: [_ | _]} = exec) do
    reraise exec.error, exec.stacktrace
  end

  def reraise_unsafe(exec), do: exec

  @spec report_finished(t()) :: t()
  def report_finished(%__MODULE__{} = exec) do
    exec
    |> record_unsaved()
    |> ack_event()
    |> emit_event()
  end

  @spec ack_event(t()) :: t()
  def ack_event(%__MODULE__{ack: true, state: :success} = exec) do
    Engine.complete_job(exec.conf, exec.job)

    exec
  end

  def ack_event(%__MODULE__{ack: true, job: job, state: :failure, worker: worker} = exec) do
    backoff = if worker, do: worker.backoff(job), else: Worker.backoff(job)

    Engine.error_job(exec.conf, job, backoff)

    exec
  end

  def ack_event(%__MODULE__{ack: true, state: :snoozed} = exec) do
    Engine.snooze_job(exec.conf, exec.job, exec.snooze)

    exec
  end

  def ack_event(%__MODULE__{ack: true, state: :cancelled} = exec) do
    Engine.cancel_job(exec.conf, exec.job)

    exec
  end

  def ack_event(%__MODULE__{ack: true, state: state} = exec)
      when state in [:discard, :exhausted] do
    Engine.discard_job(exec.conf, exec.job)

    exec
  end

  def ack_event(exec), do: exec

  @spec emit_event(t()) :: t()
  def emit_event(%__MODULE__{state: state} = exec) when state in [:failure, :exhausted] do
    measurements = %{duration: exec.duration, queue_time: exec.queue_time}

    kind =
      case exec.kind do
        {:EXIT, _pid} -> :exit
        kind when kind in [:exit, :throw, :error] -> kind
      end

    state = if state == :exhausted, do: :discard, else: state

    meta =
      Map.merge(exec.meta, %{
        job: exec.job,
        kind: kind,
        error: exec.error,
        reason: exec.error,
        stacktrace: exec.stacktrace,
        state: state
      })

    Telemetry.execute([:oban, :job, :exception], measurements, meta)

    exec
  end

  def emit_event(%__MODULE__{state: state} = exec)
      when state in [:cancelled, :success, :snoozed, :discard] do
    measurements = %{duration: exec.duration, queue_time: exec.queue_time}

    meta =
      Map.merge(exec.meta, %{
        job: exec.job,
        state: exec.state,
        result: exec.result
      })

    Telemetry.execute([:oban, :job, :stop], measurements, meta)

    exec
  end

  @spec record_unsaved(t()) :: t()
  def record_unsaved(%__MODULE__{error: error} = exec) when not is_nil(error) do
    unsaved_error = %{kind: exec.kind, reason: exec.error, stacktrace: exec.stacktrace}

    put_in(exec.job.unsaved_error, unsaved_error)
  end

  def record_unsaved(exec), do: exec

  # Helpers

  defp perform_error(worker, result), do: PerformError.exception({worker, result})

  defp event_metadata(conf, job) do
    job
    |> Map.take([:id, :args, :queue, :worker, :attempt, :max_attempts, :tags])
    |> Map.merge(%{conf: conf, job: job, prefix: conf.prefix})
  end

  defp log_warning(%__MODULE__{safe: true, worker: worker}, returned) do
    Logger.warn(fn ->
      """
      Expected #{worker}.perform/1 to return:

      - `:ok`
      - `:discard`
      - `{:ok, value}`
      - `{:error, reason}`,
      - `{:cancel, reason}`
      - `{:discard, reason}`
      - `{:snooze, seconds}`

      Instead received:

      #{inspect(returned, pretty: true)}

      The job will be considered a success.
      """
    end)
  end

  defp log_warning(_exec, _returned), do: :noop
end
