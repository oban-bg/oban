defmodule Oban.Integration.SchedulingTest do
  use Oban.Case, async: true
  use PropCheck

  alias Oban.Query

  @moduletag :integration

  @queue "scheduled"
  @demand 10

  property "jobs scheduled in the future are unavailable for execution" do
    forall seconds <- pos_integer() do
      %Job{scheduled_at: at} = insert_job!(scheduled_in: seconds)

      assert 0 < NaiveDateTime.diff(at, NaiveDateTime.utc_now())

      {count, _} = Query.fetch_available_jobs(Repo, @queue, @demand)

      assert count == 0
    end
  end

  property "jobs scheduled in the past are available for execution" do
    forall seconds <- neg_integer() do
      %Job{scheduled_at: at} = insert_job!(scheduled_in: seconds)

      assert 0 > NaiveDateTime.diff(at, NaiveDateTime.utc_now())

      {count, _} = Query.fetch_available_jobs(Repo, @queue, @demand)

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
