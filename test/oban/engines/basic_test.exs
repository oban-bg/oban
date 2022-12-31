defmodule Oban.Engines.BasicTest do
  use Oban.Case, async: true

  test "inserting and executing jobs" do
    name = start_supervised_oban!(poll_interval: 10, queues: [alpha: 3])

    changesets =
      ~w(OK CANCEL DISCARD ERROR FAIL SNOOZE)
      |> Enum.with_index(1)
      |> Enum.map(fn {act, ref} -> Worker.new(%{action: act, ref: ref}) end)

    [job_1, job_2, job_3, job_4, job_5, job_6] = Oban.insert_all(name, changesets)

    assert_receive {:ok, 1}
    assert_receive {:cancel, 2}
    assert_receive {:discard, 3}
    assert_receive {:error, 4}
    assert_receive {:fail, 5}
    assert_receive {:snooze, 6}

    with_backoff(fn ->
      assert %{state: "completed", completed_at: %_{}} = Repo.reload!(job_1)
      assert %{state: "cancelled", cancelled_at: %_{}} = Repo.reload!(job_2)
      assert %{state: "discarded", discarded_at: %_{}} = Repo.reload!(job_3)
      assert %{state: "retryable", scheduled_at: %_{}} = Repo.reload!(job_4)
      assert %{state: "retryable", scheduled_at: %_{}} = Repo.reload!(job_5)
      assert %{state: "scheduled", scheduled_at: %_{}} = Repo.reload!(job_6)
    end)
  end

  @tag :capture_log
  test "safely executing jobs with any type of exit" do
    name = start_supervised_oban!(poll_interval: 10, queues: [alpha: 3])

    changesets =
      ~w(EXIT KILL TASK_ERROR TASK_EXIT)
      |> Enum.with_index(1)
      |> Enum.map(fn {act, ref} -> Worker.new(%{action: act, ref: ref}) end)

    jobs = Oban.insert_all(name, changesets)

    assert_receive {:exit, 1}
    assert_receive {:kill, 2}
    assert_receive {:async, 3}
    assert_receive {:async, 4}

    with_backoff(fn ->
      for job <- jobs do
        assert %{state: "retryable", errors: errors, scheduled_at: %_{}} = Repo.reload!(job)
        assert [%{"attempt" => 1, "at" => _, "error" => _}] = errors
      end
    end)
  end

  test "executing jobs in order of priority" do
    name = start_supervised_oban!(poll_interval: 5, queues: [alpha: 1])

    Oban.insert_all(name, [
      Worker.new(%{action: "OK", ref: 1}, priority: 3),
      Worker.new(%{action: "OK", ref: 2}, priority: 2),
      Worker.new(%{action: "OK", ref: 3}, priority: 1),
      Worker.new(%{action: "OK", ref: 4}, priority: 0)
    ])

    assert_receive {:ok, 1}, 500
    assert_received {:ok, 2}
    assert_received {:ok, 3}
    assert_received {:ok, 4}
  end

  test "discarding jobs that exceed max attempts to" do
    name = start_supervised_oban!(poll_interval: 10, queues: [alpha: 1])

    [job_1, job_2] =
      Oban.insert_all(name, [
        Worker.new(%{action: "ERROR", ref: 1}, max_attempts: 1),
        Worker.new(%{action: "ERROR", ref: 2}, max_attempts: 2)
      ])

    assert_receive {:error, 1}
    assert_receive {:error, 2}

    with_backoff(fn ->
      assert %{state: "discarded", discarded_at: %_{}} = Repo.reload!(job_1)
      assert %{state: "retryable", scheduled_at: %_{}} = Repo.reload!(job_2)
    end)
  end

  test "ignoring available jobs that have exceeded max attempts" do
    start_supervised_oban!(poll_interval: 10, queues: [alpha: 3])

    insert!(%{ref: 1, action: "OK"}, queue: "alpha", state: "available", attempt: 19)
    insert!(%{ref: 2, action: "OK"}, queue: "alpha", state: "available", attempt: 20)

    assert_receive {:ok, 1}
    refute_receive {:ok, 2}
  end

  test "failing jobs that exceed the worker's timeout" do
    start_supervised_oban!(poll_interval: 10, queues: [alpha: 1])

    job = insert!(ref: 1, sleep: 20, timeout: 5)

    assert_receive {:started, 1}
    refute_receive {:ok, 1}

    assert %Job{state: "retryable", errors: [%{"error" => error}]} = Repo.reload(job)
    assert error == "** (Oban.TimeoutError) Oban.Integration.Worker timed out after 5ms"
  end
end
