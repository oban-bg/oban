defmodule Oban.Integration.SchedulingTest do
  use Oban.Case, async: true

  alias Oban.{Config, Query}

  @moduletag :integration

  @queue "scheduled"

  defmodule FakeWorker do
    use Oban.Worker, queue: :scheduled

    @impl Worker
    def perform(_args, _job), do: :ok
  end

  test "jobs scheduled in the future are unavailable for execution" do
    %Job{scheduled_at: at, state: "scheduled"} = insert_job!(schedule_in: 10)

    assert 0 < DateTime.diff(at, DateTime.utc_now())
    assert {0, nil} == Query.stage_scheduled_jobs(Config.new(repo: Repo), @queue)
  end

  test "jobs scheduled in the past are available for execution" do
    %Job{scheduled_at: at, state: "scheduled"} = insert_job!(schedule_in: -10)

    assert 0 > DateTime.diff(at, DateTime.utc_now())
    assert {1, nil} = Query.stage_scheduled_jobs(Config.new(repo: Repo), @queue)
  end

  test "jobs scheduled at a specific time are unavailable for execution" do
    at = DateTime.add(DateTime.utc_now(), 60)

    %Job{scheduled_at: ^at, state: "scheduled"} = insert_job!(scheduled_at: at)

    assert {0, nil} == Query.stage_scheduled_jobs(Config.new(repo: Repo), @queue)
  end

  defp insert_job!(opts) do
    %{}
    |> FakeWorker.new(opts)
    |> Repo.insert!()
  end
end
