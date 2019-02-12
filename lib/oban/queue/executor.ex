defmodule Oban.Queue.Executor do
  @moduledoc false

  alias Oban.{Config, Job, Query}

  @spec child_spec(Keyword.t()) :: Supervisor.child_spec()
  def child_spec(args) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [args]},
      type: :worker,
      restart: :temporary
    }
  end

  @spec start_link(Keyword.t(), Job.t()) :: {:ok, pid()}
  def start_link([conf: conf], job) do
    Task.start_link(__MODULE__, :call, [job, conf])
  end

  @spec call(job :: Job.t(), conf :: Config.t()) :: :ok
  def call(%Job{} = job, %Config{repo: repo}) do
    {timing, return} = :timer.tc(__MODULE__, :safe_call, [job])

    case return do
      {:success, ^job} ->
        Query.complete_job(repo, job)

        report(:success, timing, job)

      {:failure, ^job, error, stack} ->
        Query.retry_job(repo, job)

        report(:failure, timing, job, %{error: error, stack: stack})
    end

    :ok
  end

  @doc false
  def safe_call(%Job{worker: worker} = job) do
    try do
      worker
      |> to_module()
      |> apply(:perform, [job])

      {:success, job}
    rescue
      exception ->
        {:failure, job, error_name(exception), __STACKTRACE__}
    end
  end

  # Helpers

  defp to_module(worker) when is_binary(worker) do
    worker
    |> String.split(".")
    |> Module.safe_concat()
  end

  defp to_module(worker) when is_atom(worker), do: worker

  defp error_name(error) do
    %{__struct__: module} = Exception.normalize(:error, error)

    module
    |> Module.split()
    |> Enum.join(".")
  end

  defp report(event, timing, job, meta \\ %{}) do
    meta =
      job
      |> Map.take([:id, :args, :queue, :worker])
      |> Map.merge(meta)

    :telemetry.execute([:oban, :job, event], timing, meta)
  end
end
