defmodule Oban.Integration.ControllingTest do
  use Oban.Case

  @queue :control

  @oban_opts poll_interval: 10, repo: Repo, queues: [{@queue, 10}]

  # All of our tests run within the Ecto Sandbox, which executes everything inside of a
  # transaction. Postgres doesn't emit `NOTIFY` events until _after_ a transaction has completed,
  # which means our listeners will never receive an event. To work around this we send
  # notification messages to the producer directly. This reduces the reliability of our
  # integration test, but it allows us to test the functionality.

  @producer Oban.Queue.Control.Producer

  test "individual queues can be paused and resumed" do
    start_supervised!({Oban, @oban_opts})

    pause_queue(@queue)

    insert_job(ref: 1, action: "OK")

    refute_receive {:ok, 1}

    resume_queue(@queue)

    assert_receive {:ok, 1}

    stop_supervised(Oban)
  end

  test "individual queues can be scaled" do
    start_supervised!({Oban, Keyword.put(@oban_opts, :queues, control: 1)})

    for ref <- 1..20, do: insert_job(ref: ref, sleep: 50)

    scale_queue(@queue, 20)

    assert_receive {:ok, 20}

    stop_supervised(Oban)
  end

  test "executing jobs can be killed by id" do
    start_supervised!({Oban, @oban_opts})

    %Job{id: job_id} = insert_job(ref: 1, sleep: 100)

    assert_receive {:started, 1}

    kill_job(job_id)

    refute_receive {:ok, 1}, 200

    assert Repo.get(Job, job_id).state == "discarded"

    stop_supervised(Oban)
  end

  test "jobs may be dispatched from a queue via database trigger" do
    start_supervised!({Oban, Keyword.put(@oban_opts, :poll_interval, :timer.minutes(1))})

    # Producers start up asynchronously and we want to be sure the job doesn't run immediately on
    # startup.
    Process.sleep(50)

    insert_job(ref: 1, action: "OK")

    refute_receive {:ok, 1}

    # Notifications for jobs in other queues are ignored
    notify("oban_insert", "some-other-queue")
    refute_receive {:ok, 1}

    # Notifications for jobs in the same queue trigger a dispatch
    notify("oban_insert", @queue)
    assert_receive {:ok, 1}

    stop_supervised(Oban)
  end

  defp insert_job(args) do
    args
    |> Map.new()
    |> Map.put(:bin_pid, Worker.pid_to_bin())
    |> Job.new(worker: Worker, queue: @queue)
    |> Repo.insert!()
  end

  defp pause_queue(queue) do
    :ok = Oban.pause_queue(queue)

    notify(Jason.encode!(%{action: "pause", queue: queue}))
  end

  defp resume_queue(queue) do
    :ok = Oban.resume_queue(queue)

    notify(Jason.encode!(%{action: "resume", queue: queue}))
  end

  defp scale_queue(queue, scale) do
    :ok = Oban.scale_queue(queue, scale)

    notify(Jason.encode!(%{action: "scale", queue: queue, scale: scale}))
  end

  defp kill_job(job_id) do
    :ok = Oban.kill_job(job_id)

    notify(Jason.encode!(%{action: "pkill", job_id: job_id}))
  end

  defp notify(channel \\ "oban_signal", payload) do
    send(@producer, {:notification, nil, nil, channel, to_string(payload)})

    Process.sleep(50)
  end
end
