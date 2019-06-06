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
  def call(%Job{} = job, %Config{repo: repo}) do
    {duration, return} = :timer.tc(__MODULE__, :safe_call, [job])

    case return do
      {:success, ^job} ->
        Query.complete_job(repo, job)

        report(duration, job, %{event: :success})

        :success

      {:failure, ^job, kind, error, stack} ->
        Query.retry_job(repo, job, worker_backoff(job), format_blamed(kind, error, stack))

        report(duration, job, %{event: :failure, kind: kind, error: error, stack: stack})

        :failure
    end
  end

  @doc false
  def safe_call(%Job{args: args, worker: worker} = job) do
    worker
    |> to_module()
    |> apply(:perform, [args])

    {:success, job}
  rescue
    exception ->
      {:failure, job, :error, exception, __STACKTRACE__}
  catch
    kind, value ->
      {:failure, job, kind, value, __STACKTRACE__}
  end

  # Helpers

  defp to_module(worker) when is_binary(worker) do
    worker
    |> String.split(".")
    |> Module.safe_concat()
  end

  defp to_module(worker) when is_atom(worker), do: worker

  # While it is slightly wasteful, we have to convert the worker to a module again outside of
  # `safe_call/1`. There is a possibility that the worker module can't be found at all and we
  # need to fall back to a default implementation.
  defp worker_backoff(%Job{attempt: attempt, worker: worker}) do
    worker
    |> to_module()
    |> apply(:backoff, [attempt])
  rescue
    ArgumentError -> Worker.default_backoff(attempt)
  end

  defp format_blamed(kind, error, stack) do
    {blamed, stack} = Exception.blame(kind, error, stack)

    Exception.format(kind, blamed, stack)
  end

  defp report(duration, job, meta) do
    meta =
      job
      |> Map.take([:id, :args, :queue, :worker])
      |> Map.merge(meta)

    :telemetry.execute([:oban, :job, :executed], %{duration: duration}, meta)
  end
end
