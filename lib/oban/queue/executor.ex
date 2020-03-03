defmodule Oban.Queue.Executor do
  @moduledoc false

  require Logger

  alias Oban.{Breaker, Config, Job, Query, Worker}

  @type success :: {:success, Job.t()}
  @type failure :: {:failure, Job.t(), Worker.t(), atom(), term()}

  @spec call(Job.t(), Config.t()) :: :success | :failure
  def call(%Job{} = job, %Config{} = conf) do
    start_time = System.system_time(:microsecond)
    start_mono = System.monotonic_time(:microsecond)

    :telemetry.execute([:oban, :started], %{start_time: start_time}, job_meta(job))

    case safe_call(job) do
      {:success, ^job} ->
        Breaker.with_retry(fn -> report_success(conf, job, start_mono) end)

      {:failure, ^job, kind, error, stack} ->
        Breaker.with_retry(fn -> report_failure(conf, job, start_mono, kind, error, stack) end)
    end
  end

  @spec safe_call(Job.t()) :: success() | failure()
  def safe_call(%Job{} = job) do
    case Job.worker_module(job) do
      {:ok, worker} ->
        case worker.timeout(job) do
          :infinity ->
            perform_inline(worker, job)

          timeout when is_integer(timeout) ->
            perform_timed(worker, job, timeout)
        end

      {:error, error, stacktrace} ->
        {:failure, job, :error, error, stacktrace}
    end
  end

  @spec perform_inline(Worker.t(), Job.t()) :: success() | failure()
  def perform_inline(worker, %Job{args: args} = job) do
    case worker.perform(args, job) do
      :ok ->
        {:success, job}

      {:ok, _result} ->
        {:success, job}

      {:error, error} ->
        {:failure, job, :error, error, current_stacktrace()}

      returned ->
        Logger.warn(fn ->
          """
          Expected #{worker}.perform/2 to return :ok, `{:ok, value}`, or {:error, reason}. Instead
          received:

          #{inspect(returned, pretty: true)}

          The job will be considered a success.
          """
        end)

        {:success, job}
    end
  rescue
    exception ->
      {:failure, job, :exception, exception, __STACKTRACE__}
  catch
    kind, value ->
      {:failure, job, kind, value, __STACKTRACE__}
  end

  @spec perform_timed(Worker.t(), Job.t(), timeout()) :: success() | failure()
  def perform_timed(worker, job, timeout) do
    task = Task.async(fn -> perform_inline(worker, job) end)

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, reply} ->
        reply

      nil ->
        {:failure, job, :error, :timeout, current_stacktrace()}
    end
  end

  @spec report_success(Config.t(), Job.t(), integer()) :: :success
  def report_success(conf, job, start_mono) do
    Query.complete_job(conf, job)

    :telemetry.execute([:oban, :success], %{duration: duration(start_mono)}, job_meta(job))

    :success
  end

  @spec report_failure(Config.t(), Job.t(), integer(), atom(), any(), list()) :: :failure
  def report_failure(conf, job, start_mono, kind, error, stack) do
    Query.retry_job(conf, job, worker_backoff(job), kind, error, stack)

    meta =
      job
      |> job_meta()
      |> Map.merge(%{kind: kind, error: error, stack: stack})

    :telemetry.execute([:oban, :failure], %{duration: duration(start_mono)}, meta)

    :failure
  end

  # Helpers

  defp current_stacktrace do
    self()
    |> Process.info(:current_stacktrace)
    |> elem(1)
  end

  defp duration(start_mono), do: System.monotonic_time(:microsecond) - start_mono

  defp job_meta(job), do: Map.take(job, [:id, :args, :queue, :worker, :attempt, :max_attempts])

  defp worker_backoff(%Job{attempt: attempt} = job) do
    case Job.worker_module(job) do
      {:ok, worker} -> worker.backoff(attempt)
      _ -> Worker.default_backoff(attempt)
    end
  end
end
