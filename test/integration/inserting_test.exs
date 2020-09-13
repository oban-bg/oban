defmodule Oban.Integration.InsertingTest do
  use Oban.Case, async: true

  alias Ecto.Multi

  test "inserting multiple jobs within a multi using insert/3" do
    name = start_supervised_oban!(queues: false)

    multi = Multi.new()
    multi = Oban.insert(name, multi, :job_1, Worker.new(%{ref: 1}))
    multi = Oban.insert(name, multi, "job-2", fn _ -> Worker.new(%{ref: 2}) end)
    multi = Oban.insert(name, multi, {:job, 3}, Worker.new(%{ref: 3}))
    assert {:ok, results} = Repo.transaction(multi)

    assert %{:job_1 => job_1, "job-2" => job_2, {:job, 3} => job_3} = results

    assert job_1.id
    assert job_2.id
    assert job_3.id
  end

  test "inserting multiple jobs with insert_all/2" do
    name = start_supervised_oban!(queues: false)

    changesets = Enum.map(0..4, &Worker.new(%{ref: &1}, queue: "special", schedule_in: 10))
    jobs = Oban.insert_all(name, changesets)

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
    name = start_supervised_oban!(queues: false)

    changesets_1 = Enum.map(1..2, &Worker.new(%{ref: &1}))
    changesets_2 = Enum.map(3..4, &Worker.new(%{ref: &1}))

    multi = Ecto.Multi.new()
    multi = Oban.insert_all(name, multi, "jobs-1", changesets_1)
    multi = Oban.insert_all(name, multi, "jobs-2", changesets_2)
    {:ok, %{"jobs-1" => jobs_1, "jobs-2" => jobs_2}} = Repo.transaction(multi)

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
