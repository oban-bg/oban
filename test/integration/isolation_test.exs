defmodule Oban.Integration.IsolationTest do
  use Oban.Case

  use Oban.Testing, repo: Oban.Test.Repo, prefix: "private"

  @moduletag :integration

  test "inserting jobs with a custom prefix" do
    name = start_supervised_oban!(prefix: "private")

    insert!(name, %{ref: 1, action: "OK"}, [])

    assert_enqueued worker: Worker
  end

  test "assuring that the perform will execute with custom prefix" do
    assert :ok = perform_job(Worker, %{ref: 1, action: "OK"}, prefix: "private")
    assert :discard = perform_job(Worker, %{ref: 1, action: "DISCARD"}, prefix: "private")
    assert {:error, _} = perform_job(Worker, %{ref: 1, action: "ERROR"}, prefix: "private")
  end

  test "inserting and executing unique jobs with a custom prefix" do
    name = start_supervised_oban!(prefix: "private", queues: [alpha: 5])

    insert!(name, %{ref: 1, action: "OK"}, unique: [period: 60, fields: [:worker]])
    insert!(name, %{ref: 2, action: "OK"}, unique: [period: 60, fields: [:worker]])

    assert_receive {:ok, 1}
    refute_receive {:ok, 2}
  end

  test "controlling jobs with a custom prefix" do
    name = start_supervised_oban!(prefix: "private", queues: [alpha: 5])

    insert!(name, %{ref: 1}, schedule_in: 10)
    insert!(name, %{ref: 2}, schedule_in: 10)
    insert!(name, %{ref: 3}, schedule_in: 10)

    assert {:ok, 3} = Oban.cancel_all_jobs(name, Job)
    assert {:ok, 3} = Oban.retry_all_jobs(name, Job)
  end
end
