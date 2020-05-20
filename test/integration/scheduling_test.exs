defmodule Oban.Integration.SchedulingTest do
  use Oban.Case, async: true

  alias Oban.{Config, Query}

  @moduletag :integration

  test "jobs scheduled in the future are unavailable for execution" do
    %Job{scheduled_at: at, state: "scheduled"} = insert!(%{}, schedule_in: 10)

    assert 0 < DateTime.diff(at, DateTime.utc_now())
    assert {0, nil} == Query.stage_scheduled_jobs(Config.new(repo: Repo), "alpha")
  end

  test "jobs scheduled in the past are available for execution" do
    %Job{scheduled_at: at, state: "scheduled"} = insert!(%{}, schedule_in: -10)

    assert 0 > DateTime.diff(at, DateTime.utc_now())
    assert {1, nil} = Query.stage_scheduled_jobs(Config.new(repo: Repo), "alpha")
  end

  test "jobs scheduled at a specific time are unavailable for execution" do
    at = DateTime.add(DateTime.utc_now(), 60)

    %Job{scheduled_at: ^at, state: "scheduled"} = insert!(%{}, scheduled_at: at)

    assert {0, nil} == Query.stage_scheduled_jobs(Config.new(repo: Repo), "alpha")
  end
end
