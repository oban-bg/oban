defmodule Oban.Integration.ControllingTest do
  use Oban.Case

  @oban_opts poll_interval: 10, repo: Repo

  # All of our tests run within the Ecto Sandbox, which executes everything inside of a
  # transaction. Postgres doesn't emit `NOTIFY` events until _after_ a transaction has completed,
  # which means our listeners will never receive an event. To work around this we both call the
  # function on `Oban` and send a notification event to the producer directly. This reduces the
  # reliability of our integration test, but it allows us to test the functionality.
  @producer Oban.Queue.Control.Producer

  test "individual queues can be paused and resumed" do
    start_supervised!({Oban, Keyword.put(@oban_opts, :queues, control: 10)})

    pause_queue(:control)

    insert_job(ref: 1, action: "OK")

    refute_receive {:ok, 1}

    resume_queue(:control)

    assert_receive {:ok, 1}

    stop_supervised(Oban)
  end

  test "individual queues can be scaled" do
    start_supervised!({Oban, Keyword.put(@oban_opts, :queues, control: 1)})

    for ref <- 1..20, do: insert_job(ref: ref, sleep: 50)

    scale_queue(:control, 20)

    assert_receive {:ok, 20}

    stop_supervised(Oban)
  end

  test "executing jobs can be killed by id" do
    start_supervised!({Oban, Keyword.put(@oban_opts, :queues, control: 10)})

    %Job{id: job_id} = insert_job(ref: 1, sleep: 100)

    assert_receive {:started, 1}

    kill_job(job_id)

    refute_receive {:ok, 1}, 200

    assert Repo.get(Job, job_id).state == "discarded"

    stop_supervised(Oban)
  end

  defp insert_job(args) do
    args
    |> Map.new()
    |> Map.put(:bin_pid, Worker.pid_to_bin())
    |> Job.new(worker: Worker, queue: "control")
    |> Repo.insert!()
  end

  defp pause_queue(queue) do
    :ok = Oban.pause_queue(:control)

    notify(%{action: "pause", queue: queue})
  end

  defp resume_queue(queue) do
    :ok = Oban.resume_queue(queue)

    notify(%{action: "resume", queue: queue})
  end

  defp scale_queue(queue, scale) do
    :ok = Oban.scale_queue(queue, scale)

    notify(%{action: "scale", queue: queue, scale: scale})
  end

  defp kill_job(job_id) do
    :ok = Oban.kill_job(job_id)

    notify(%{action: "pkill", job_id: job_id})
  end

  defp notify(payload) do
    send(@producer, {:notification, nil, nil, "oban_control", Jason.encode!(payload)})

    Process.sleep(50)
  end
end
