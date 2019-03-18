defmodule Oban.Integration.ControllingTest do
  use Oban.Case

  @oban_opts poll_interval: 10, repo: Repo, queues: [control: 10]

  test "individual queues can be paused and started" do
    start_supervised!({Oban, @oban_opts})

    assert :ok = Oban.pause_queue(:control)

    insert_job(ref: 1, action: "OK")

    refute_receive {:ok, 1}

    assert :ok = Oban.resume_queue(:control)

    assert_receive {:ok, 1}

    stop_supervised(Oban)
  end

  defp insert_job(args) do
    args
    |> Map.new()
    |> Map.put(:bin_pid, Worker.pid_to_bin())
    |> Job.new(worker: Worker, queue: "control")
    |> Repo.insert!()
  end
end
