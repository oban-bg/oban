defmodule Oban.Integration.ControllingTest do
  use Oban.Case

  alias Oban.{Notifier, Registry}

  @moduletag :integration

  describe "start_queue/2" do
    test "validating options" do
      name = start_supervised_oban!(queues: [])

      assert_invalid_opts(name, :start_queue, [])
      assert_invalid_opts(name, :start_queue, queue: nil)
      assert_invalid_opts(name, :start_queue, limit: -1)
      assert_invalid_opts(name, :start_queue, local_only: -1)
      assert_invalid_opts(name, :start_queue, wat: -1)
    end

    test "starting individual queues dynamically" do
      name = start_supervised_oban!(queues: [alpha: 9])

      assert :ok = Oban.start_queue(name, queue: :gamma, limit: 5, refresh_interval: 10)
      assert :ok = Oban.start_queue(name, queue: :delta, limit: 6, paused: true)
      assert :ok = Oban.start_queue(name, queue: :alpha, limit: 5)

      with_backoff(fn ->
        assert %{limit: 9} = Oban.check_queue(name, queue: :alpha)
        assert %{limit: 5, refresh_interval: 10} = Oban.check_queue(name, queue: :gamma)
        assert %{limit: 6, paused: true} = Oban.check_queue(name, queue: :delta)
      end)
    end

    test "starting individual queues only on the local node" do
      name1 = start_supervised_oban!(queues: [])
      name2 = start_supervised_oban!(queues: [])

      assert :ok = Oban.start_queue(name1, queue: :alpha, limit: 1, local_only: true)

      with_backoff(fn ->
        assert supervised_queue?(name1, "alpha")
        refute supervised_queue?(name2, "alpha")
      end)
    end
  end

  describe "stop_queue/2" do
    test "validating options" do
      name = start_supervised_oban!(queues: [])

      assert_invalid_opts(name, :start_queue, queue: nil)
      assert_invalid_opts(name, :start_queue, local_only: -1)
    end

    test "stopping individual queues" do
      name = start_supervised_oban!(queues: [alpha: 5, delta: 5, gamma: 5])

      assert supervised_queue?(name, "delta")
      assert supervised_queue?(name, "gamma")

      assert :ok = Oban.stop_queue(name, queue: :delta)
      assert :ok = Oban.stop_queue(name, queue: :gamma)

      with_backoff(fn ->
        assert supervised_queue?(name, "alpha")
        refute supervised_queue?(name, "delta")
        refute supervised_queue?(name, "gamma")
      end)
    end

    test "stopping individual queues only on the local node" do
      name1 = start_supervised_oban!(queues: [alpha: 1])
      name2 = start_supervised_oban!(queues: [alpha: 1])

      wait_for_notifier(name2)

      assert :ok = Oban.stop_queue(name2, queue: :alpha, local_only: true)

      with_backoff(fn ->
        assert supervised_queue?(name1, "alpha")
        refute supervised_queue?(name2, "alpha")
      end)
    end
  end

  describe "pause_queue/2 and resume_queue/2" do
    test "validating options" do
      name = start_supervised_oban!(queues: [])

      assert_invalid_opts(name, :pause_queue, queue: nil)
      assert_invalid_opts(name, :pause_queue, local_only: -1)

      assert_invalid_opts(name, :resume_queue, queue: nil)
      assert_invalid_opts(name, :resume_queue, local_only: -1)
    end

    test "pausing and resuming individual queues" do
      name = start_supervised_oban!(queues: [alpha: 5])

      wait_for_notifier(name)

      assert :ok = Oban.pause_queue(name, queue: :alpha)

      with_backoff(fn ->
        assert %{paused: true} = Oban.check_queue(name, queue: :alpha)
      end)

      assert :ok = Oban.resume_queue(name, queue: :alpha)

      with_backoff(fn ->
        assert %{paused: false} = Oban.check_queue(name, queue: :alpha)
      end)
    end

    test "pausing queues only on the local node" do
      name1 = start_supervised_oban!(queues: [alpha: 1])
      name2 = start_supervised_oban!(queues: [alpha: 1])

      wait_for_notifier(name2)

      assert :ok = Oban.pause_queue(name2, queue: :alpha, local_only: true)

      with_backoff(fn ->
        assert %{paused: false} = Oban.check_queue(name1, queue: :alpha)
        assert %{paused: true} = Oban.check_queue(name2, queue: :alpha)
      end)
    end

    test "resuming queues only on the local node" do
      name1 = start_supervised_oban!(queues: [alpha: 1])
      name2 = start_supervised_oban!(queues: [alpha: 1])

      wait_for_notifier(name1)
      wait_for_notifier(name2)

      assert :ok = Oban.pause_queue(name1, queue: :alpha)

      with_backoff(fn ->
        assert %{paused: true} = Oban.check_queue(name1, queue: :alpha)
        assert %{paused: true} = Oban.check_queue(name2, queue: :alpha)
      end)

      assert :ok = Oban.resume_queue(name1, queue: :alpha, local_only: true)

      with_backoff(fn ->
        assert %{paused: false} = Oban.check_queue(name1, queue: :alpha)
        assert %{paused: true} = Oban.check_queue(name2, queue: :alpha)
      end)
    end
  end

  describe "scale_queue/2" do
    test "validating options" do
      name = start_supervised_oban!(queues: [])

      assert_invalid_opts(name, :scale_queue, [])
      assert_invalid_opts(name, :scale_queue, queue: nil)
      assert_invalid_opts(name, :scale_queue, limit: -1)
      assert_invalid_opts(name, :scale_queue, local_only: -1)
    end

    test "scaling queues up" do
      name = start_supervised_oban!(queues: [alpha: 1])

      wait_for_notifier(name)

      assert :ok = Oban.scale_queue(name, queue: :alpha, limit: 5)

      with_backoff(fn ->
        assert %{limit: 5} = Oban.check_queue(name, queue: :alpha)
      end)
    end

    test "forwarding scaling options for alternative engines" do
      # This is an abuse of `scale` because other engines support other options and passing
      # `paused` verifies that other options are supported.
      name = start_supervised_oban!(queues: [alpha: 1])

      wait_for_notifier(name)

      assert :ok = Oban.scale_queue(name, queue: :alpha, limit: 5, paused: true)

      with_backoff(fn ->
        assert %{limit: 5, paused: true} = Oban.check_queue(name, queue: :alpha)
      end)
    end

    test "scaling queues only on the local node" do
      name1 = start_supervised_oban!(queues: [alpha: 2])
      name2 = start_supervised_oban!(queues: [alpha: 2])

      wait_for_notifier(name1)
      wait_for_notifier(name2)

      assert :ok = Oban.scale_queue(name2, queue: :alpha, limit: 1, local_only: true)

      with_backoff(fn ->
        assert %{limit: 2} = Oban.check_queue(name1, queue: :alpha)
        assert %{limit: 1} = Oban.check_queue(name2, queue: :alpha)
      end)
    end
  end

  test "killing an executing job by its id" do
    name = start_supervised_oban!(queues: [alpha: 5])

    job = insert!(ref: 1, sleep: 100)

    assert_receive {:started, 1}

    Oban.cancel_job(name, job.id)

    refute_receive {:ok, 1}, 200

    assert %Job{state: "cancelled", cancelled_at: %_{}} = Repo.reload(job)

    assert %{running: []} = Oban.check_queue(name, queue: :alpha)
  end

  test "cancelling jobs that may or may not be executing" do
    name = start_supervised_oban!(queues: [alpha: 5])

    job_a = insert!(%{ref: 1}, schedule_in: 10)
    job_b = insert!(%{ref: 2}, schedule_in: 10, state: "retryable")
    job_c = insert!(%{ref: 3}, state: "completed")
    job_d = insert!(%{ref: 4, sleep: 100})

    assert_receive {:started, 4}

    assert :ok = Oban.cancel_job(name, job_a.id)
    assert :ok = Oban.cancel_job(name, job_b.id)
    assert :ok = Oban.cancel_job(name, job_c.id)
    assert :ok = Oban.cancel_job(name, job_d.id)

    refute_receive {:ok, 4}, 200

    assert %Job{state: "cancelled", cancelled_at: %_{}} = Repo.reload(job_a)
    assert %Job{state: "cancelled", cancelled_at: %_{}} = Repo.reload(job_b)
    assert %Job{state: "completed", cancelled_at: nil} = Repo.reload(job_c)
    assert %Job{state: "cancelled", cancelled_at: %_{}} = Repo.reload(job_d)
  end

  test "cancelling all jobs that may or may not be executing" do
    name = start_supervised_oban!(queues: [alpha: 5])

    job_a = insert!(%{ref: 1}, schedule_in: 10)
    job_b = insert!(%{ref: 2}, schedule_in: 10, state: "retryable")
    job_c = insert!(%{ref: 3}, state: "completed")
    job_d = insert!(%{ref: 4, sleep: 100})

    assert_receive {:started, 4}

    assert {:ok, 3} = Oban.cancel_all_jobs(name, Job)

    refute_receive {:ok, 4}, 200

    assert %Job{state: "cancelled", cancelled_at: %_{}} = Repo.reload(job_a)
    assert %Job{state: "cancelled", cancelled_at: %_{}} = Repo.reload(job_b)
    assert %Job{state: "completed", cancelled_at: nil} = Repo.reload(job_c)
    assert %Job{state: "cancelled", cancelled_at: %_{}} = Repo.reload(job_d)
  end

  test "dispatching jobs from a queue via database trigger" do
    name = start_supervised_oban!(queues: [alpha: 5])

    wait_for_notifier(name)

    insert!(ref: 1, action: "OK")

    assert_receive {:ok, 1}
  end

  test "retrying jobs from multiple states" do
    name = start_supervised_oban!(queues: [])

    job_a = insert!(%{ref: 1}, state: "discarded", max_attempts: 20, attempt: 20)
    job_b = insert!(%{ref: 2}, state: "completed", max_attempts: 20)
    job_c = insert!(%{ref: 3}, state: "available", max_attempts: 20)
    job_d = insert!(%{ref: 4}, state: "retryable", max_attempts: 20)
    job_e = insert!(%{ref: 5}, state: "executing", max_attempts: 1, attempt: 1)
    job_f = insert!(%{ref: 6}, state: "scheduled", max_attempts: 1, attempt: 1)

    assert :ok = Oban.retry_job(name, job_a.id)
    assert :ok = Oban.retry_job(name, job_b.id)
    assert :ok = Oban.retry_job(name, job_c.id)
    assert :ok = Oban.retry_job(name, job_d.id)
    assert :ok = Oban.retry_job(name, job_e.id)
    assert :ok = Oban.retry_job(name, job_f.id)

    assert %Job{state: "available", max_attempts: 21} = Repo.reload(job_a)
    assert %Job{state: "available", max_attempts: 20} = Repo.reload(job_b)
    assert %Job{state: "available", max_attempts: 20} = Repo.reload(job_c)
    assert %Job{state: "available", max_attempts: 20} = Repo.reload(job_d)
    assert %Job{state: "executing", max_attempts: 1} = Repo.reload(job_e)
    assert %Job{state: "scheduled", max_attempts: 1} = Repo.reload(job_f)
  end

  test "retrying all retryable jobs" do
    name = start_supervised_oban!(queues: [])

    job_a = insert!(%{ref: 1}, state: "discarded", max_attempts: 20, attempt: 20)
    job_b = insert!(%{ref: 2}, state: "completed", max_attempts: 20)
    job_c = insert!(%{ref: 3}, state: "available", max_attempts: 20)
    job_d = insert!(%{ref: 4}, state: "retryable", max_attempts: 20)
    job_e = insert!(%{ref: 5}, state: "executing", max_attempts: 1, attempt: 1)
    job_f = insert!(%{ref: 6}, state: "scheduled", max_attempts: 1, attempt: 1)

    assert {:ok, 3} = Oban.retry_all_jobs(name, Job)

    assert %Job{state: "available", max_attempts: 21} = Repo.reload(job_a)
    assert %Job{state: "available", max_attempts: 20} = Repo.reload(job_b)
    assert %Job{state: "available", max_attempts: 20} = Repo.reload(job_c)
    assert %Job{state: "available", max_attempts: 20} = Repo.reload(job_d)
    assert %Job{state: "executing", max_attempts: 1} = Repo.reload(job_e)
    assert %Job{state: "scheduled", max_attempts: 1} = Repo.reload(job_f)
  end

  defp supervised_queue?(oban_name, queue_name) do
    oban_name
    |> Registry.whereis({:producer, queue_name})
    |> is_pid()
  end

  defp wait_for_notifier(oban_name) do
    with_backoff(fn ->
      notifier_state =
        oban_name
        |> Registry.via(Notifier)
        |> :sys.get_state()

      assert is_pid(notifier_state.conn)
    end)
  end

  defp assert_invalid_opts(oban_name, function_name, opts) do
    assert_raise ArgumentError, fn -> apply(oban_name, function_name, [opts]) end
  end
end
