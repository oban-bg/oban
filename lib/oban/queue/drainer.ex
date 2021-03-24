defmodule Oban.Queue.Drainer do
  @moduledoc false

  import Ecto.Query, only: [where: 3]

  alias Oban.{Config, Job, Repo}
  alias Oban.Queue.{BasicEngine, Executor}

  @infinite 100_000_000

  def drain(%Config{} = conf, [_ | _] = opts) do
    args =
      opts
      |> Keyword.put_new(:with_recursion, false)
      |> Keyword.put_new(:with_safety, true)
      |> Keyword.put_new(:with_scheduled, false)
      |> Keyword.update!(:queue, &to_string/1)
      |> Map.new()

    drain(conf, %{failure: 0, success: 0}, args)
  end

  defp stage_scheduled(conf, queue) do
    query =
      Job
      |> where([j], j.state in ["scheduled", "retryable"])
      |> where([j], j.queue == ^queue)

    Repo.update_all(conf, query, set: [state: "available"])
  end

  defp fetch_available(conf, queue) do
    {:ok, meta} = BasicEngine.init(conf, queue: queue, limit: @infinite)
    {:ok, {_meta, jobs}} = BasicEngine.fetch_jobs(conf, meta, %{})

    jobs
  end

  defp drain(conf, old_acc, %{queue: queue} = args) do
    if args.with_scheduled, do: stage_scheduled(conf, queue)

    new_acc =
      conf
      |> fetch_available(args.queue)
      |> Enum.reduce(old_acc, fn job, acc ->
        result =
          conf
          |> Executor.new(job)
          |> Executor.put(:safe, args.with_safety)
          |> Executor.call()

        Map.update(acc, result, 1, &(&1 + 1))
      end)

    if args.with_recursion and old_acc != new_acc do
      drain(conf, new_acc, args)
    else
      new_acc
    end
  end
end
