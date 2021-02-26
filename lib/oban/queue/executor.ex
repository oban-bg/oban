defmodule Oban.Queue.Executor do
  @moduledoc false

  alias Oban.{
    Breaker,
    Config,
    CrashError,
    Job,
    PerformError,
    Query,
    Telemetry,
    TimeoutError,
    Worker
  }

  require Logger

  @type success :: {:success, Job.t()}
  @type failure :: {:failure, Job.t(), Worker.t(), atom(), term()}

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
          worker: Worker.t(),
          safe: boolean(),
          snooze: pos_integer(),
          stacktrace: Exception.stacktrace(),
          state: :unset | :discard | :failure | :success | :snoozed
        }

  @enforce_keys [:conf, :job]
  defstruct [
    :conf,
    :error,
    :job,
    :meta,
    :result,
    :snooze,
    :start_mono,
    :start_time,
    :stop_mono,
    :worker,
    safe: true,
    duration: 0,
    kind: :error,
    queue_time: 0,
    stacktrace: [],
    state: :unset
  ]

  @spec new(Config.t(), Job.t()) :: t()
  def new(%Config{} = conf, %Job{} = job) do
    struct!(__MODULE__,
      conf: conf,
      job: job,
      meta: event_metadata(conf, job),
      start_mono: System.monotonic_time(),
      start_time: System.system_time()
    )
  end

  @spec put(t(), :safe, boolean()) :: t()
  def put(%__MODULE__{} = exec, :safe, value) when is_boolean(value) do
    %{exec | safe: value}
  end

  @spec call(t()) :: :success | :failure
  def call(%__MODULE__{} = exec) do
    exec =
      exec
      |> record_started()
      |> resolve_worker()
      |> perform()
      |> record_finished()

    Breaker.with_retry(fn -> report_finished(exec).state end)
  end

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

  @spec perform(t()) :: t()
  def perform(%__MODULE__{state: :unset} = exec) do
    case exec.worker.timeout(exec.job) do
      :infinity ->
        perform_inline(exec)

      timeout when is_integer(timeout) ->
        perform_timed(exec, timeout)
    end
  end

  def perform(%__MODULE__{} = exec), do: exec

  @spec record_finished(t()) :: t()
  def record_finished(%__MODULE__{} = exec) do
    stop_mono = System.monotonic_time()
    duration = stop_mono - exec.start_mono
    queue_time = DateTime.diff(exec.job.attempted_at, exec.job.scheduled_at, :nanosecond)

    %{exec | duration: duration, queue_time: queue_time, stop_mono: stop_mono}
  end

  @spec report_finished(t()) :: t()
  def report_finished(%__MODULE__{} = exec) do
    case exec.state do
      :success ->
        Query.complete_job(exec.conf, exec.job)

        execute_stop(exec)

      :failure ->
        job = job_with_unsaved_error(exec)

        Query.retry_job(exec.conf, job, backoff(exec.worker, job))

        execute_exception(exec)

      :snoozed ->
        Query.snooze_job(exec.conf, exec.job, exec.snooze)

        execute_stop(exec)

      :discard ->
        Query.discard_job(exec.conf, job_with_unsaved_error(exec))

        execute_stop(exec)
    end

    exec
  end

  defp perform_inline(%{safe: true} = exec) do
    perform_inline(%{exec | safe: false})
  rescue
    error ->
      %{exec | state: :failure, error: error, stacktrace: __STACKTRACE__}
  catch
    kind, reason ->
      error = CrashError.exception({kind, reason, __STACKTRACE__})

      %{exec | state: :failure, error: error, stacktrace: __STACKTRACE__}
  end

  defp perform_inline(%{worker: worker, job: job} = exec) do
    case worker.perform(job) do
      :ok ->
        %{exec | state: :success, result: :ok}

      {:ok, _value} = result ->
        %{exec | state: :success, result: result}

      :discard ->
        %{exec | state: :discard, error: PerformError.exception({worker, :discard})}

      {:discard, reason} ->
        %{exec | state: :discard, error: PerformError.exception({worker, {:discard, reason}})}

      {:error, reason} ->
        %{exec | state: :failure, error: PerformError.exception({worker, {:error, reason}})}

      {:snooze, seconds} ->
        %{exec | state: :snoozed, snooze: seconds}

      returned ->
        Logger.warn(fn ->
          """
          Expected #{worker}.perform/1 to return:

          - `:ok`
          - `:discard`
          - `{:ok, value}`
          - `{:error, reason}`,
          - `{:discard, reason}`
          - `{:snooze, seconds}`

          Instead received:

          #{inspect(returned, pretty: true)}

          The job will be considered a success.
          """
        end)

        %{exec | state: :success}
    end
  end

  defp perform_timed(exec, timeout) do
    task = Task.async(fn -> perform_inline(exec) end)

    # Stash the timed task's pid to facilitate sending it messages via telemetry events.
    Process.put(:"$nested", [task.pid])

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, reply} ->
        reply

      nil ->
        error = TimeoutError.exception({exec.worker, timeout})

        %{exec | state: :failure, error: error}
    end
  end

  defp backoff(nil, job), do: Worker.backoff(job)
  defp backoff(worker, job), do: worker.backoff(job)

  defp execute_stop(exec) do
    measurements = %{duration: exec.duration, queue_time: exec.queue_time}

    meta =
      exec.meta
      |> Map.put(:state, exec.state)
      |> Map.put(:result, exec.result)

    Telemetry.execute([:oban, :job, :stop], measurements, meta)
  end

  defp execute_exception(exec) do
    measurements = %{duration: exec.duration, queue_time: exec.queue_time}

    meta =
      Map.merge(exec.meta, %{
        kind: exec.kind,
        error: exec.error,
        stacktrace: exec.stacktrace,
        state: exec.state
      })

    Telemetry.execute([:oban, :job, :exception], measurements, meta)
  end

  defp event_metadata(conf, job) do
    job
    |> Map.take([:id, :args, :queue, :worker, :attempt, :max_attempts, :tags])
    |> Map.put(:conf, conf)
    |> Map.put(:job, job)
    |> Map.put(:prefix, conf.prefix)
  end

  defp job_with_unsaved_error(%__MODULE__{} = exec) do
    %{
      exec.job
      | unsaved_error: %{kind: exec.kind, reason: exec.error, stacktrace: exec.stacktrace}
    }
  end
end
