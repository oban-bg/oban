defmodule Oban.Integration.InsertingTest do
  use Oban.Case, async: true

  alias Ecto.Multi

  test "inserting job with insert/2" do
    start_supervised_oban!(name: Oban, queues: false)
    assert {:ok, %Job{}} = Oban.insert(Worker.new(%{ref: 1}), timeout: 10_000)

    name = start_supervised_oban!(queues: false)
    assert {:ok, %Job{}} = Oban.insert(name, Worker.new(%{ref: 2}))
  end

  test "inserting multiple jobs within a multi using insert/4" do
    name = start_supervised_oban!(queues: false)

    multi_1 = Multi.new()
    multi_1 = Oban.insert(name, multi_1, :job_1, Worker.new(%{ref: 1}))
    multi_1 = Oban.insert(name, multi_1, "job-2", fn _ -> Worker.new(%{ref: 2}) end)
    multi_1 = Oban.insert(name, multi_1, {:job, 3}, Worker.new(%{ref: 3}))
    assert {:ok, results_1} = Repo.transaction(multi_1)

    assert %{:job_1 => job_1, "job-2" => job_2, {:job, 3} => job_3} = results_1

    assert job_1.id
    assert job_2.id
    assert job_3.id

    start_supervised_oban!(name: Oban, queues: false)

    multi_2 = Multi.new()
    multi_2 = Oban.insert(multi_2, :job_4, Worker.new(%{ref: 4}), timeout: 10_000)
    assert {:ok, results_2} = Repo.transaction(multi_2)

    assert %{:job_4 => job_4} = results_2

    assert job_4.id
  end

  test "inserting job with insert!/2" do
    start_supervised_oban!(name: Oban, queues: false)
    assert %Job{} = Oban.insert!(Worker.new(%{ref: 1}), timeout: 10_000)

    name = start_supervised_oban!(queues: false)
    assert %Job{} = Oban.insert!(name, Worker.new(%{ref: 2}))
  end

  test "inserting multiple jobs with insert_all/2" do
    start_supervised_oban!(name: Oban, queues: false)

    changesets_1 = Enum.map(0..4, &Worker.new(%{ref: &1}, queue: "special", schedule_in: 10))
    jobs_1 = Oban.insert_all(changesets_1, timeout: 10_000)

    assert is_list(jobs_1)
    assert length(jobs_1) == 5

    [%Job{queue: "special", state: "scheduled"} = job_1 | _] = jobs_1

    assert job_1.id
    assert job_1.args
    assert job_1.scheduled_at

    name = start_supervised_oban!(queues: false)

    changesets_2 = Enum.map(5..9, &Worker.new(%{ref: &1}, queue: "special", schedule_in: 10))
    jobs_2 = Oban.insert_all(name, changesets_2)

    assert is_list(jobs_2)
    assert length(jobs_2) == 5

    [%Job{queue: "special", state: "scheduled"} = job_2 | _] = jobs_2

    assert job_2.id
    assert job_2.args
    assert job_2.scheduled_at
  end

  test "inserting multiple jobs from a changeset wrapper with insert_all/2" do
    name = start_supervised_oban!(queues: false)
    wrap = %{changesets: [Worker.new(%{ref: 0}), Worker.new(%{ref: 1})]}

    [_job_1, _job_2] = Oban.insert_all(name, wrap)
  end

  test "handling empty changesets list from wrapper using insert_all/4" do
    name = start_supervised_oban!(queues: false)

    assert {:ok, %{jobs: []}} =
             name
             |> Oban.insert_all(Multi.new(), :jobs, %{changesets: []})
             |> Repo.transaction()
  end

  test "handling empty changesets list from wrapper with insert_all/2" do
    name = start_supervised_oban!(queues: false)

    assert [] = Oban.insert_all(name, %{changesets: []})
  end

  test "inserting multiple jobs within a multi using insert_all/4" do
    name = start_supervised_oban!(queues: false)

    changesets_1 = Enum.map(1..2, &Worker.new(%{ref: &1}))
    changesets_2 = Enum.map(3..4, &Worker.new(%{ref: &1}))
    changesets_3 = Enum.map(5..6, &Worker.new(%{ref: &1}))

    multi_1 = Multi.new()
    multi_1 = Oban.insert_all(name, multi_1, "jobs-1", changesets_1)
    multi_1 = Oban.insert_all(name, multi_1, "jobs-2", changesets_2)
    multi_1 = Multi.run(multi_1, "build-jobs-3", fn _, _ -> {:ok, changesets_3} end)
    multi_1 = Oban.insert_all(name, multi_1, "jobs-3", & &1["build-jobs-3"])

    {:ok, %{"jobs-1" => jobs_1, "jobs-2" => jobs_2, "jobs-3" => jobs_3}} =
      Repo.transaction(multi_1)

    assert [%Job{}, %Job{}] = jobs_1
    assert [%Job{}, %Job{}] = jobs_2
    assert [%Job{}, %Job{}] = jobs_3

    start_supervised_oban!(name: Oban, queues: false)

    changesets_4 = Enum.map(7..8, &Worker.new(%{ref: &1}))

    multi_2 = Multi.new()
    multi_2 = Oban.insert_all(multi_2, "jobs-4", changesets_4, timeout: 10_000)

    {:ok, %{"jobs-4" => jobs_4}} = Repo.transaction(multi_2)

    assert [%Job{}, %Job{}] = jobs_4
  end

  test "inserting multiple jobs from a changeset wrapper using insert_all/4" do
    name = start_supervised_oban!(queues: false)
    wrap = %{changesets: [Worker.new(%{ref: 0})]}

    multi = Multi.new()
    multi = Oban.insert_all(name, multi, "jobs-1", wrap)
    multi = Oban.insert_all(name, multi, "jobs-2", fn _ -> wrap end)

    {:ok, %{"jobs-1" => [_job_1], "jobs-2" => [_job_2]}} = Repo.transaction(multi)
  end

  test "inserting multiple jobs with additional options" do
    name = start_supervised_oban!(queues: false)

    assert [%Job{}] = Oban.insert_all(name, [Worker.new(%{ref: 0})], timeout: 1_000)
  end
end
