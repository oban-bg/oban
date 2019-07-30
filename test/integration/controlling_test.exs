defmodule Oban.Integration.ControllingTest do
  use Oban.Case

  @moduletag :integration

  @oban_opts repo: Repo, queues: [control: 10, default: 5]

  test "individual queues can be paused and resumed" do
    start_supervised!({Oban, @oban_opts})

    # Pause briefly so that the producer has time to subscribe to notifications.
    Process.sleep(10)

    Oban.pause_queue(:control)

    insert_job!(ref: 1, action: "OK")

    refute_receive {:ok, 1}

    Oban.resume_queue(:control)

    assert_receive {:ok, 1}

    stop_supervised(Oban)
  end

  test "individual queues can be scaled" do
    start_supervised!({Oban, Keyword.put(@oban_opts, :queues, control: 1)})

    for ref <- 1..20, do: insert_job!(ref: ref, sleep: 50)

    Oban.scale_queue(:control, 20)

    assert_receive {:ok, 20}

    stop_supervised(Oban)
  end

  test "executing jobs can be killed by id" do
    start_supervised!({Oban, @oban_opts})

    %Job{id: job_id} = insert_job!(ref: 1, sleep: 100)

    assert_receive {:started, 1}

    Oban.kill_job(job_id)

    refute_receive {:ok, 1}, 200

    assert Repo.get(Job, job_id).state == "discarded"

    stop_supervised(Oban)
  end

  test "jobs may be dispatched from a queue via database trigger" do
    start_supervised!({Oban, Keyword.put(@oban_opts, :poll_interval, :timer.minutes(5))})

    # Producers start up asynchronously and we want to be sure the job doesn't run immediately on
    # startup.
    Process.sleep(50)

    insert_job!(ref: 1, action: "OK")

    assert_receive {:ok, 1}

    stop_supervised(Oban)
  end

  defp insert_job!(args) do
    args
    |> Worker.new(queue: :control)
    |> Oban.insert!()
  end
end
