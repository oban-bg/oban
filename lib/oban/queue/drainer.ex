defmodule Oban.Queue.Drainer do
  @moduledoc false

  import Ecto.Query, only: [where: 3]

  alias Oban.{Config, Job, Repo}
  alias Oban.Queue.Executor

  @infinite 100_000_000

  def drain(%Config{} = conf, [_ | _] = opts) do
    args =
      opts
      |> Map.new()
      |> Map.put_new(:with_limit, @infinite)
      |> Map.put_new(:with_recursion, false)
      |> Map.put_new(:with_safety, true)
      |> Map.put_new(:with_scheduled, false)
      |> Map.update!(:queue, &to_string/1)

    drain(conf, %{cancelled: 0, discard: 0, failure: 0, snoozed: 0, success: 0}, args)
  end

  defp stage_scheduled(conf, queue, with_scheduled) do
    query =
      Job
      |> where([j], j.state in ["scheduled", "retryable"])
      |> where([j], j.queue == ^queue)

    query =
      case with_scheduled do
        true -> query
        %DateTime{} -> where(query, [j], j.scheduled_at <= ^with_scheduled)
      end

    Repo.update_all(conf, query, set: [state: "available"])
  end

  defp drain(conf, old_acc, %{queue: queue} = args) do
    if args.with_scheduled, do: stage_scheduled(conf, queue, args.with_scheduled)

    new_acc =
      conf
      |> fetch_available(args)
      |> Enum.reduce(old_acc, fn job, acc ->
        result =
          conf
          |> Executor.new(job, safe: args.with_safety)
          |> Executor.call()
          |> case do
            %{state: :exhausted} -> :discard
            %{state: state} -> state
          end

        Map.update(acc, result, 1, &(&1 + 1))
      end)

    if args.with_recursion and old_acc != new_acc do
      drain(conf, new_acc, args)
    else
      new_acc
    end
  end

  defp fetch_available(conf, %{queue: queue, with_limit: limit}) do
    {:ok, meta} = conf.engine.init(conf, queue: queue, limit: limit)
    {:ok, {_meta, jobs}} = conf.engine.fetch_jobs(conf, meta, %{})

    jobs
  end
end
