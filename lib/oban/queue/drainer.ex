defmodule Oban.Queue.Drainer do
  @moduledoc false

  import Ecto.Query, only: [where: 3]

  alias Oban.{Config, Job, Query, Repo}
  alias Oban.Queue.Executor

  @unlimited 100_000_000
  @fake_nonce "draining"

  def drain(%Config{} = conf, [_ | _] = opts) do
    queue =
      opts
      |> Keyword.fetch!(:queue)
      |> to_string()

    if Keyword.get(opts, :with_scheduled, false), do: stage_scheduled(conf, queue)

    conf
    |> fetch_available(queue)
    |> Enum.reduce(%{failure: 0, success: 0}, fn job, acc ->
      result =
        conf
        |> Executor.new(job)
        |> Executor.put(:safe, Keyword.get(opts, :with_safety, true))
        |> Executor.call()

      Map.update(acc, result, 1, &(&1 + 1))
    end)
  end

  defp stage_scheduled(conf, queue) do
    query =
      Job
      |> where([j], j.state in ["scheduled", "retryable"])
      |> where([j], j.queue == ^queue)

    Repo.update_all(conf, query, set: [state: "available"])
  end

  defp fetch_available(conf, queue) do
    {:ok, jobs} = Query.fetch_available_jobs(conf, queue, @fake_nonce, @unlimited)

    jobs
  end
end
