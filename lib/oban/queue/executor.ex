defmodule Oban.Queue.Executor do
  @moduledoc false

  require Logger

  alias Oban.{Breaker, Config, Job, Query, Worker}

  @type success :: {:success, Job.t()}
  @type failure :: {:failure, Job.t(), Worker.t(), atom(), term(), list()}

  @spec call(Job.t(), Config.t()) :: :success | :failure
  def call(%Job{} = job, %Config{} = conf) do
    {duration, return} = :timer.tc(__MODULE__, :safe_call, [job])

    case return do
      {:success, ^job} ->
        Breaker.with_retry(fn -> report_success(conf, job, duration) end)

      {:failure, ^job, kind, error, stack} ->
        Breaker.with_retry(fn -> report_failure(conf, job, duration, kind, error, stack) end)
    end
  end

  @spec safe_call(Job.t()) :: success() | failure()
  def safe_call(%Job{} = job) do
    case Job.worker_module(job) do
      {:ok, worker} ->
        perform(worker, job)

      {:error, error, stacktrace} ->
        {:failure, job, :error, error, stacktrace}
    end
  end

  @spec report_success(Config.t(), Job.t(), integer()) :: :success
  def report_success(conf, job, duration) do
    Query.complete_job(conf, job)

    report(:success, duration, job, %{})
  end

  @spec report_failure(Config.t(), Job.t(), integer(), atom(), any(), list()) :: :failure
  def report_failure(conf, job, duration, kind, error, stack) do
    Query.retry_job(conf, job, worker_backoff(job), kind, error, stack)

    report(:failure, duration, job, %{kind: kind, error: error, stack: stack})
  end

  # Helpers

  defp worker_backoff(%Job{attempt: attempt} = job) do
    case Job.worker_module(job) do
      {:ok, worker} -> worker.backoff(attempt)
      _ -> Worker.default_backoff(attempt)
    end
  end

  defp perform(worker, %Job{args: args} = job) do
    case worker.perform(args, job) do
      :ok ->
        {:success, job}

      {:ok, _result} ->
        {:success, job}

      {:error, error} ->
        {:current_stacktrace, stacktrace} = Process.info(self(), :current_stacktrace)

        {:failure, job, :error, error, stacktrace}

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

  defp report(event, duration, job, meta) do
    meta =
      job
      |> Map.take([:id, :args, :queue, :worker, :attempt, :max_attempts])
      |> Map.merge(meta)

    :telemetry.execute([:oban, event], %{duration: duration}, meta)

    event
  end
end
