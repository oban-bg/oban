defmodule Oban.Integration.ControllingTest do
  use Oban.Case

  @moduletag :integration

  describe "start_queue/2" do
    test "validating options" do
      start_supervised_oban!(queues: false)

      assert_invalid_start([queue: nil], ~r/expected :queue to be a binary or atom/)
      assert_invalid_start([limit: -1], ~r/expected :limit to be a positive integer/)
      assert_invalid_start([local_only: -1], ~r/expected :local_only to be a boolean/)
      assert_invalid_start([wat: -1], ~r/unknown option provided/)
    end

    test "starting individual queues dynamically" do
      start_supervised_oban!(queues: [alpha: 10])

      insert!(%{ref: 1, action: "OK"}, queue: :gamma)
      insert!(%{ref: 2, action: "OK"}, queue: :delta)

      refute_receive {:ok, 1}
      refute_receive {:ok, 2}

      assert :ok = Oban.start_queue(queue: :gamma, limit: 5)
      assert :ok = Oban.start_queue(queue: :delta, limit: 6)
      assert :ok = Oban.start_queue(queue: :alpha, limit: 5)

      assert_receive {:ok, 1}
      assert_receive {:ok, 2}
    end

    test "starting individual queues only on the local node" do
      start_supervised_oban!(name: ObanA, queues: [])
      start_supervised_oban!(name: ObanB, queues: [])

      assert :ok = Oban.start_queue(ObanA, queue: :alpha, limit: 1, local_only: true)

      with_backoff(fn ->
        assert supervised_queue?(ObanA, ObanA.Queue.Alpha)
        refute supervised_queue?(ObanB, ObanB.Queue.Alpha)
      end)
    end
  end

  describe "stop_queue/2" do
    test "validating options" do
      start_supervised_oban!(queues: false)

      assert_invalid_stop([queue: nil], ~r/expected :queue to be a binary or atom/)
      assert_invalid_stop([local_only: -1], ~r/expected :local_only to be a boolean/)
      assert_invalid_stop([wat: -1], ~r/unknown option provided/)
    end

    test "stopping individual queues" do
      start_supervised_oban!(queues: [alpha: 5, delta: 5, gamma: 5])

      assert supervised_queue?(Oban.Queue.Delta)
      assert supervised_queue?(Oban.Queue.Gamma)

      insert!(%{ref: 1, action: "OK"}, queue: :delta)
      insert!(%{ref: 2, action: "OK"}, queue: :gamma)

      assert_receive {:ok, 1}
      assert_receive {:ok, 2}

      assert :ok = Oban.stop_queue(queue: :delta)
      assert :ok = Oban.stop_queue(queue: :gamma)

      with_backoff(fn ->
        refute supervised_queue?(Oban.Queue.Delta)
        refute supervised_queue?(Oban.Queue.Gamma)
      end)

      insert!(%{ref: 3, action: "OK"}, queue: :alpha)
      insert!(%{ref: 4, action: "OK"}, queue: :delta)
      insert!(%{ref: 5, action: "OK"}, queue: :gamma)

      assert_receive {:ok, 3}
      refute_receive {:ok, 4}
      refute_receive {:ok, 5}
    end

    test "stopping individual queues only on the local node" do
      start_supervised_oban!(name: ObanA, queues: [alpha: 1])
      start_supervised_oban!(name: ObanB, queues: [alpha: 1])

      assert :ok = Oban.stop_queue(ObanB, queue: :alpha, local_only: true)

      with_backoff(fn ->
        assert supervised_queue?(ObanA, ObanA.Queue.Alpha)
        refute supervised_queue?(ObanB, Oban.Queue.Alpha)
      end)
    end
  end

  test "pausing and resuming individual queues" do
    start_supervised_oban!(queues: [alpha: 5], poll_interval: 1_000)

    # Pause briefly so that the producer has time to subscribe to notifications.
    Process.sleep(20)

    assert :ok = Oban.pause_queue(:alpha)

    insert!(ref: 1, action: "OK")

    refute_receive {:ok, 1}

    assert :ok = Oban.resume_queue(:alpha)

    assert_receive {:ok, 1}
  end

  test "scaling individual queues" do
    start_supervised_oban!(queues: [alpha: 1])

    for ref <- 1..20, do: insert!(ref: ref, sleep: 50)

    Oban.scale_queue(:alpha, 20)

    assert_receive {:ok, 20}
  end

  test "killing an executing job by its id" do
    start_supervised_oban!(queues: [alpha: 5])

    job = insert!(ref: 1, sleep: 100)

    assert_receive {:started, 1}

    Oban.cancel_job(job.id)

    refute_receive {:ok, 1}, 200

    assert %Job{state: "discarded", discarded_at: %DateTime{}} = Repo.reload(job)

    %{running: running} = :sys.get_state(Oban.Queue.Alpha.Producer)

    assert Enum.empty?(running)
  end

  test "cancelling jobs that may or may not be executing" do
    start_supervised_oban!(queues: [alpha: 5])

    job_a = insert!(%{ref: 1}, schedule_in: 10)
    job_b = insert!(%{ref: 2}, schedule_in: 10, state: "retryable")
    job_c = insert!(%{ref: 3}, state: "completed")
    job_d = insert!(%{ref: 4, sleep: 100})

    assert_receive {:started, 4}

    assert :ok = Oban.cancel_job(job_a.id)
    assert :ok = Oban.cancel_job(job_b.id)
    assert :ok = Oban.cancel_job(job_c.id)
    assert :ok = Oban.cancel_job(job_d.id)

    refute_receive {:ok, 4}, 200

    assert %Job{state: "discarded", discarded_at: %DateTime{}} = Repo.reload(job_a)
    assert %Job{state: "discarded", discarded_at: %DateTime{}} = Repo.reload(job_b)
    assert %Job{state: "completed", discarded_at: nil} = Repo.reload(job_c)
    assert %Job{state: "discarded", discarded_at: %DateTime{}} = Repo.reload(job_d)
  end

  test "dispatching jobs from a queue via database trigger" do
    start_supervised_oban!(queues: [alpha: 5], poll_interval: :timer.minutes(5))

    # Producers start up asynchronously and we want to be sure the job doesn't run immediately on
    # startup.
    Process.sleep(50)

    insert!(ref: 1, action: "OK")

    assert_receive {:ok, 1}

    :ok = stop_supervised(Oban)
  end

  defp supervised_queue?(sup \\ Oban, queue_name) do
    sup
    |> Supervisor.which_children()
    |> Enum.any?(fn {name, _, _, _} -> name == queue_name end)
  end

  defp assert_invalid_stop(opts, message) do
    assert_raise ArgumentError, message, fn ->
      Oban.stop_queue(opts)
    end
  end

  defp assert_invalid_start(opts, message) do
    assert_raise ArgumentError, message, fn ->
      Oban.start_queue(opts)
    end
  end
end
