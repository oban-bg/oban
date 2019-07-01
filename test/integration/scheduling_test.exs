defmodule Oban.Integration.SchedulingTest do
  use Oban.Case, async: true
  use PropCheck

  alias Oban.{Config, Query}

  @moduletag :integration

  @queue "scheduled"

  property "jobs scheduled in the future are unavailable for execution" do
    forall seconds <- pos_integer() do
      %Job{scheduled_at: at, state: state} = insert_job!(schedule_in: seconds)

      assert 0 < NaiveDateTime.diff(at, NaiveDateTime.utc_now())
      assert state == "scheduled"

      assert {0, nil} == Query.stage_scheduled_jobs(Config.new(repo: Repo), @queue)
    end
  end

  property "jobs scheduled in the past are available for execution" do
    forall seconds <- neg_integer() do
      %Job{scheduled_at: at, state: state} = insert_job!(schedule_in: seconds)

      assert 0 > NaiveDateTime.diff(at, NaiveDateTime.utc_now())
      assert state == "scheduled"

      {count, _} = Query.stage_scheduled_jobs(Config.new(repo: Repo), @queue)

      assert count > 0
    end
  end

  defp insert_job!(opts) do
    opts = Keyword.merge(opts, worker: FakeWorker, queue: @queue)

    %{}
    |> Job.new(opts)
    |> Repo.insert!()
  end
end
