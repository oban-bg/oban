defmodule Oban.Integration.ControllingTest do
  use Oban.Case

  @moduletag :integration

  test "starting individual queues dynamically" do
    start_supervised_oban!(queues: [alpha: 10])

    insert!(%{ref: 1, action: "OK"}, queue: :gamma)
    insert!(%{ref: 2, action: "OK"}, queue: :delta)

    refute_receive {:ok, 1}
    refute_receive {:ok, 2}

    assert :ok = Oban.start_queue(:gamma, 5)
    assert :ok = Oban.start_queue(:delta, 6)
    assert :ok = Oban.start_queue(:alpha, 5)

    assert_receive {:ok, 1}
    assert_receive {:ok, 2}
  end

  test "stopping individual queues" do
    start_supervised_oban!(queues: [alpha: 5, delta: 5, gamma: 5])

    assert supervised_queue?(Oban.Queue.Delta)
    assert supervised_queue?(Oban.Queue.Gamma)

    insert!(%{ref: 1, action: "OK"}, queue: :delta)
    insert!(%{ref: 2, action: "OK"}, queue: :gamma)

    assert_receive {:ok, 1}
    assert_receive {:ok, 2}

    assert :ok = Oban.stop_queue(:delta)
    assert :ok = Oban.stop_queue(:gamma)

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

    Oban.kill_job(job.id)

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

    assert %Job{state: "discarded", discarded_at: %DateTime{}} = Repo.reload(job_a)
    assert %Job{state: "discarded", discarded_at: %DateTime{}} = Repo.reload(job_b)
    assert %Job{state: "completed", discarded_at: nil} = Repo.reload(job_c)
    assert %Job{state: "discarded", discarded_at: %DateTime{}} = Repo.reload(job_d)

    refute_receive {:ok, 4}, 200
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

  defp supervised_queue?(queue_name) do
    Oban
    |> Supervisor.which_children()
    |> Enum.any?(fn {name, _, _, _} -> name == queue_name end)
  end
end
