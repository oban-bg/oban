defmodule Oban.Queue.Executor do
  @moduledoc false

  require Logger

  alias Oban.{Breaker, Config, Job, Query, Worker}

  @type success :: {:success, Job.t()}
  @type failure :: {:failure, Job.t(), Worker.t(), atom(), term()}

  @type t :: %__MODULE__{
          conf: Config.t(),
          duration: pos_integer(),
          job: Job.t(),
          kind: any(),
          meta: map(),
          start_mono: integer(),
          start_time: integer(),
          stop_mono: integer(),
          worker: Worker.t(),
          safe: boolean(),
          stack: list(),
          state: :unset | :failure | :success
        }

  @enforce_keys [:conf, :job]
  defstruct [
    :conf,
    :error,
    :job,
    :kind,
    :meta,
    :start_mono,
    :start_time,
    :stop_mono,
    :worker,
    safe: true,
    duration: 0,
    stack: [],
    state: :unset
  ]

  @spec new(Config.t(), Job.t()) :: t()
  def new(%Config{} = conf, %Job{} = job) do
    struct!(__MODULE__,
      conf: conf,
      job: job,
      meta: Map.take(job, [:id, :args, :queue, :worker, :attempt, :max_attempts]),
      start_mono: System.monotonic_time(:microsecond),
      start_time: System.system_time(:microsecond)
    )
  end

  @spec put(t(), atom(), any()) :: t()
  def put(%__MODULE__{} = exec, key, value) when is_atom(key) do
    %{exec | key => value}
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

  @spec record_started(t()) :: t()
  def record_started(%__MODULE__{} = exec) do
    :telemetry.execute([:oban, :started], %{start_time: exec.start_time}, exec.meta)

    exec
  end

  @spec resolve_worker(t()) :: t()
  def resolve_worker(%__MODULE__{safe: true} = exec) do
    %{resolve_worker(%{exec | safe: false}) | safe: true}
  rescue
    error -> %{exec | state: :failure, error: error, stack: __STACKTRACE__}
  end

  def resolve_worker(%__MODULE__{} = exec) do
    worker =
      exec.job.worker
      |> String.split(".")
      |> Module.safe_concat()

    %{exec | worker: worker}
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
    stop_mono = System.monotonic_time(:microsecond)

    %{exec | duration: stop_mono - exec.start_mono, stop_mono: stop_mono}
  end

  @spec report_finished(t()) :: t()
  def report_finished(%__MODULE__{} = exec) do
    case exec.state do
      :success ->
        Query.complete_job(exec.conf, exec.job)

        :telemetry.execute([:oban, :success], %{duration: exec.duration}, exec.meta)

      :failure ->
        Query.retry_job(exec.conf, exec.job, backoff(exec), exec.kind, exec.error, exec.stack)

        meta = Map.merge(exec.meta(), %{kind: exec.kind, error: exec.error, stack: exec.stack})

        :telemetry.execute([:oban, :failure], %{duration: exec.duration}, meta)
    end

    exec
  end

  defp perform_inline(%{safe: true} = exec) do
    perform_inline(%{exec | safe: false})
  rescue
    error ->
      %{exec | state: :failure, kind: :exception, error: error, stack: __STACKTRACE__}
  catch
    kind, value ->
      %{exec | state: :failure, kind: kind, error: value, stack: __STACKTRACE__}
  end

  defp perform_inline(%{worker: worker, job: job} = exec) do
    case worker.perform(job.args, job) do
      :ok ->
        %{exec | state: :success}

      {:ok, _result} ->
        %{exec | state: :success}

      {:error, error} ->
        %{exec | state: :failure, kind: :error, error: error, stack: current_stacktrace()}

      returned ->
        Logger.warn(fn ->
          """
          Expected #{worker}.perform/2 to return :ok, `{:ok, value}`, or {:error, reason}. Instead
          received:

          #{inspect(returned, pretty: true)}

          The job will be considered a success.
          """
        end)

        %{exec | state: :success}
    end
  end

  defp perform_timed(exec, timeout) do
    task = Task.async(fn -> perform_inline(exec) end)

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, reply} ->
        reply

      nil ->
        %{exec | state: :failure, kind: :error, error: :timeout, stack: current_stacktrace()}
    end
  end

  defp backoff(%{worker: nil, job: job}), do: Worker.backoff(job.attempt)
  defp backoff(%{worker: worker, job: job}), do: worker.backoff(job.attempt)

  defp current_stacktrace do
    self()
    |> Process.info(:current_stacktrace)
    |> elem(1)
  end
end
