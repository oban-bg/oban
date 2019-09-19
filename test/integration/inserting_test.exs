defmodule Oban.Integration.InsertingTest do
  use Oban.Case, async: true

  @moduletag :integration

  @oban_opts repo: Repo, queues: false

  test "inserting multiple jobs with insert_all/2" do
    start_supervised!({Oban, @oban_opts})

    jobs =
      0..4
      |> Enum.map(&Worker.new(%{ref: &1}, queue: "special", schedule_in: 10))
      |> Oban.insert_all()

    assert is_list(jobs)
    assert length(jobs) == 5

    [%Job{} = job | _] = jobs

    assert job.id
    assert job.args
    assert job.queue == "special"
    assert job.state == "scheduled"
    assert job.scheduled_at
  end

  test "inserting multiple jobs within a multi using insert_all/4" do
    start_supervised!({Oban, @oban_opts})

    changesets = Enum.map(1..5, &Worker.new(%{ref: &1}))

    {:ok, %{jobs: jobs}} =
      Ecto.Multi.new()
      |> Oban.insert_all(:jobs, changesets)
      |> Repo.transaction()

    assert is_list(jobs)
    assert length(jobs) == 5

    [%Job{} = job | _] = jobs

    assert job.id
    assert job.args
  end
end
