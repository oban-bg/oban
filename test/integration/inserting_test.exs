defmodule Oban.Integration.InsertingTest do
  use Oban.Case, async: true

  alias Ecto.Multi

  @moduletag :integration

  @oban_opts repo: Repo, queues: false

  test "inserting multiple jobs within a multi using insert/3" do
    start_supervised!({Oban, @oban_opts})

    assert {:ok, results} =
             Multi.new()
             |> Oban.insert(:job_1, Worker.new(%{ref: 1}))
             |> Oban.insert("job-2", Worker.new(%{ref: 2}))
             |> Oban.insert({:job, 3}, Worker.new(%{ref: 3}))
             |> Repo.transaction()

    assert %{:job_1 => job_1, "job-2" => job_2, {:job, 3} => job_3} = results

    assert job_1.id
    assert job_2.id
    assert job_3.id
  end

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

    changesets_1 = Enum.map(1..2, &Worker.new(%{ref: &1}))
    changesets_2 = Enum.map(3..4, &Worker.new(%{ref: &1}))

    {:ok, %{"jobs-1" => jobs_1, "jobs-2" => jobs_2}} =
      Ecto.Multi.new()
      |> Oban.insert_all("jobs-1", changesets_1)
      |> Oban.insert_all("jobs-2", changesets_2)
      |> Repo.transaction()

    assert is_list(jobs_1)
    assert length(jobs_1) == 2
    assert [%Job{} = job | _] = jobs_1

    assert job.id
    assert job.args

    assert is_list(jobs_2)
    assert length(jobs_2) == 2
    assert [%Job{} = job | _] = jobs_2

    assert job.id
    assert job.args
  end
end
