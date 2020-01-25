defmodule Oban.Queue.Executor do
  @moduledoc false

  alias Oban.{Config, Job, Query, Worker}

  @spec child_spec(Job.t(), Config.t()) :: Supervisor.child_spec()
  def child_spec(job, conf) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [job, conf]},
      type: :worker,
      restart: :temporary
    }
  end

  @spec start_link(Job.t(), Config.t()) :: {:ok, pid()}
  def start_link(%Job{} = job, %Config{} = conf) do
    Task.start_link(__MODULE__, :call, [job, conf])
  end

  @spec call(Job.t(), Config.t()) :: :success | :failure
  def call(%Job{} = job, %Config{} = conf) do
    {duration, return} = :timer.tc(__MODULE__, :safe_call, [job])

    case return do
      {:success, ^job} ->
        Query.complete_job(conf, job)

        report(:success, duration, job, %{})

      {:failure, ^job, kind, error, stack} ->
        Query.retry_job(conf, job, worker_backoff(job), format_blamed(kind, error, stack))

        report(:failure, duration, job, %{kind: kind, error: error, stack: stack})
    end
  end

  @doc false
  def safe_call(%Job{} = job) do
    with {:ok, worker} <- worker_module(job) do
      case worker.timeout(job) do
        :infinity ->
          perform_inline(worker, job)

        timeout when is_integer(timeout) ->
          perform_task(worker, job, timeout)
      end
    end
  end

  defp perform_task(worker, job, timeout) do
    task = Task.async(fn -> perform_inline(worker, job) end)

    case Task.yield(task, timeout) || Task.shutdown(task) do
      # reply here could still be a job failure, or even an exception tuple
      # it just indicates that the job didn't timeout
      {:ok, reply} ->
        reply

      nil ->
        {:current_stacktrace, stacktrace} = Process.info(self(), :current_stacktrace)
        {:failure, job, :timeout, timeout, stacktrace}
    end
  end

  defp perform_inline(worker, %{args: args} = job) do
    worker
    |> apply(:perform, [args, job])
    |> case do
      {:error, error} ->
        {:current_stacktrace, stacktrace} = Process.info(self(), :current_stacktrace)

        {:failure, job, :error, error, stacktrace}

      _ ->
        {:success, job}
    end
  rescue
    exception ->
      {:failure, job, :exception, exception, __STACKTRACE__}
  catch
    kind, value ->
      {:failure, job, kind, value, __STACKTRACE__}
  end

  # Helpers

  defp worker_module(%Job{worker: worker} = job) when is_binary(worker) do
    {:ok,
     worker
     |> String.split(".")
     |> Module.safe_concat()}
  rescue
    exception ->
      {:failure, job, :exception, exception, __STACKTRACE__}
  end

  defp worker_module(%Job{worker: worker}) when is_atom(worker), do: {:ok, worker}

  # While it is slightly wasteful, we have to convert the worker to a module again outside of
  # `safe_call/1`. There is a possibility that the worker module can't be found at all and we
  # need to fall back to a default implementation.
  defp worker_backoff(%Job{attempt: attempt} = job) do
    case worker_module(job) do
      {:ok, module} ->
        module.backoff(attempt)

      _ ->
        Worker.default_backoff(attempt)
    end
  end

  defp format_blamed(:exception, error, stack), do: format_blamed(:error, error, stack)

  defp format_blamed(kind, error, stack) do
    {blamed, stack} = Exception.blame(kind, error, stack)

    Exception.format(kind, blamed, stack)
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
