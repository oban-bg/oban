defmodule Oban.Queue.Executor do
  @moduledoc false

  require Logger

  alias Oban.{Breaker, Config, Job, Query, Worker}

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
        Breaker.with_retry(fn ->
          Query.complete_job(conf, job)

          report(:success, duration, job, %{})
        end)

      {:failure, ^job, kind, error, stack} ->
        Breaker.with_retry(fn ->
          Query.retry_job(conf, job, worker_backoff(job), format_blamed(kind, error, stack))

          report(:failure, duration, job, %{kind: kind, error: error, stack: stack})
        end)
    end
  end

  @doc false
  def safe_call(%Job{args: args, worker: worker} = job) do
    worker
    |> to_module()
    |> apply(:perform, [args, job])
    |> case do
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
    module =
      try do
        to_module(worker)
      rescue
        ArgumentError -> nil
      end

    if function_exported?(module, :backoff, 1) do
      module.backoff(attempt)
    else
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
