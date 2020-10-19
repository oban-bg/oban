defmodule Oban.Integration.ControllingTest do
  use Oban.Case

  @moduletag :integration

  describe "start_queue/2" do
    test "validating options" do
      assert_invalid_opts(:start_queue, queue: nil)
      assert_invalid_opts(:start_queue, limit: -1)
      assert_invalid_opts(:start_queue, local_only: -1)
      assert_invalid_opts(:start_queue, wat: -1)
    end

    test "starting individual queues dynamically" do
      name = start_supervised_oban!(queues: [alpha: 10])

      insert!(%{ref: 1, action: "OK"}, queue: :gamma)
      insert!(%{ref: 2, action: "OK"}, queue: :delta)

      refute_receive {:ok, 1}
      refute_receive {:ok, 2}

      assert :ok = Oban.start_queue(name, queue: :gamma, limit: 5)
      assert :ok = Oban.start_queue(name, queue: :delta, limit: 6)
      assert :ok = Oban.start_queue(name, queue: :alpha, limit: 5)

      assert_receive {:ok, 1}
      assert_receive {:ok, 2}
    end

    test "starting individual queues only on the local node" do
      name1 = start_supervised_oban!(queues: [])
      name2 = start_supervised_oban!(queues: [])

      sleep_for_notifier()

      assert :ok = Oban.start_queue(name1, queue: :alpha, limit: 1, local_only: true)

      with_backoff(fn ->
        assert supervised_queue?(name1, "alpha")
        refute supervised_queue?(name2, "alpha")
      end)
    end
  end

  describe "stop_queue/2" do
    test "validating options" do
      assert_invalid_opts(:start_queue, queue: nil)
      assert_invalid_opts(:start_queue, local_only: -1)
    end

    test "stopping individual queues" do
      name = start_supervised_oban!(queues: [alpha: 5, delta: 5, gamma: 5])

      assert supervised_queue?(name, "delta")
      assert supervised_queue?(name, "gamma")

      insert!(%{ref: 1, action: "OK"}, queue: :delta)
      insert!(%{ref: 2, action: "OK"}, queue: :gamma)

      assert_receive {:ok, 1}
      assert_receive {:ok, 2}

      assert :ok = Oban.stop_queue(name, queue: :delta)
      assert :ok = Oban.stop_queue(name, queue: :gamma)

      with_backoff(fn ->
        refute supervised_queue?(name, "delta")
        refute supervised_queue?(name, "gamma")
      end)

      insert!(%{ref: 3, action: "OK"}, queue: :alpha)
      insert!(%{ref: 4, action: "OK"}, queue: :delta)
      insert!(%{ref: 5, action: "OK"}, queue: :gamma)

      assert_receive {:ok, 3}
      refute_receive {:ok, 4}
      refute_receive {:ok, 5}
    end

    test "stopping individual queues only on the local node" do
      name1 = start_supervised_oban!(queues: [alpha: 1])
      name2 = start_supervised_oban!(queues: [alpha: 1])

      sleep_for_notifier()

      assert :ok = Oban.stop_queue(name2, queue: :alpha, local_only: true)

      with_backoff(fn ->
        assert supervised_queue?(name1, "alpha")
        refute supervised_queue?(name2, "alpha")
      end)
    end
  end

  describe "pause_queue/2 and resume_queue/2" do
    test "validating options" do
      assert_invalid_opts(:pause_queue, queue: nil)
      assert_invalid_opts(:pause_queue, local_only: -1)

      assert_invalid_opts(:resume_queue, queue: nil)
      assert_invalid_opts(:resume_queue, local_only: -1)
    end

    test "pausing and resuming individual queues" do
      name = start_supervised_oban!(queues: [alpha: 5], poll_interval: 1_000)

      sleep_for_notifier()

      assert :ok = Oban.pause_queue(name, queue: :alpha)

      insert!(ref: 1, action: "OK")

      refute_receive {:ok, 1}

      assert :ok = Oban.resume_queue(name, queue: :alpha)

      assert_receive {:ok, 1}
    end

    test "pausing queues only on the local node" do
      start_supervised_oban!(queues: [alpha: 1])
      name2 = start_supervised_oban!(queues: [alpha: 1])

      sleep_for_notifier()

      assert :ok = Oban.pause_queue(name2, queue: :alpha, local_only: true)

      insert!(%{ref: 1, sleep: 500}, queue: :alpha)
      insert!(%{ref: 2, sleep: 500}, queue: :alpha)

      assert_receive {:started, 1}
      refute_receive {:started, 2}
    end

    test "resuming queues only on the local node" do
      name1 = start_supervised_oban!(queues: [alpha: 1])
      start_supervised_oban!(queues: [alpha: 1])

      sleep_for_notifier()

      assert :ok = Oban.pause_queue(name1, queue: :alpha)
      assert :ok = Oban.resume_queue(name1, queue: :alpha, local_only: true)

      insert!(%{ref: 1, sleep: 500}, queue: :alpha)
      insert!(%{ref: 2, sleep: 500}, queue: :alpha)

      assert_receive {:started, 1}
      refute_receive {:started, 2}
    end
  end

  describe "scale_queue/2" do
    test "validating options" do
      assert_invalid_opts(:scale_queue, queue: nil)
      assert_invalid_opts(:scale_queue, limit: -1)
      assert_invalid_opts(:scale_queue, local_only: -1)
    end

    test "scaling queues up" do
      name = start_supervised_oban!(queues: [alpha: 1])

      sleep_for_notifier()

      for ref <- 1..6, do: insert!(ref: ref, sleep: 500)

      assert :ok = Oban.scale_queue(name, queue: :alpha, limit: 5)

      assert_receive {:started, 5}
      refute_receive {:started, 6}
    end

    test "scaling queues only on the local node" do
      start_supervised_oban!(queues: [alpha: 2])
      name2 = start_supervised_oban!(queues: [alpha: 2])

      sleep_for_notifier()

      assert :ok = Oban.scale_queue(name2, queue: :alpha, limit: 1, local_only: true)

      for ref <- 1..4, do: insert!(ref: ref, sleep: 1000)

      assert_receive {:started, 1}
      assert_receive {:started, 2}
      assert_receive {:started, 3}
      refute_receive {:started, 4}
    end
  end

  test "killing an executing job by its id" do
    name = start_supervised_oban!(queues: [alpha: 5])

    job = insert!(ref: 1, sleep: 100)

    assert_receive {:started, 1}

    Oban.cancel_job(name, job.id)

    refute_receive {:ok, 1}, 200

    assert %Job{state: "cancelled", discarded_at: %_{}, errors: [_]} = Repo.reload(job)

    %{running: running} = :sys.get_state(Oban.Registry.whereis(name, {:producer, "alpha"}))

    assert Enum.empty?(running)
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

    assert %Job{state: "cancelled", discarded_at: %_{}} = Repo.reload(job_a)
    assert %Job{state: "cancelled", discarded_at: %_{}} = Repo.reload(job_b)
    assert %Job{state: "completed", discarded_at: nil} = Repo.reload(job_c)
    assert %Job{state: "cancelled", discarded_at: %_{}} = Repo.reload(job_d)
  end

  test "dispatching jobs from a queue via database trigger" do
    start_supervised_oban!(queues: [alpha: 5], poll_interval: :timer.minutes(5))

    sleep_for_notifier()

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

  defp supervised_queue?(oban_name, queue_name) do
    oban_name
    |> Oban.whereis()
    |> Supervisor.which_children()
    |> Enum.any?(fn {name, _, _, _} -> name == queue_name end)
  end

  defp sleep_for_notifier do
    Process.sleep(25)
  end

  defp assert_invalid_opts(function_name, opts) do
    assert_raise ArgumentError, fn -> apply(Oban, function_name, [opts]) end
  end
end
