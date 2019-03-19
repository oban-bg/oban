defmodule Oban.Integration.ControllingTest do
  use Oban.Case

  @oban_opts poll_interval: 10, repo: Repo

  test "individual queues can be paused and resumed" do
    start_supervised!({Oban, Keyword.put(@oban_opts, :queues, control: 10)})

    assert :ok = Oban.pause_queue(:control)

    insert_job(ref: 1, action: "OK")

    refute_receive {:ok, 1}

    assert :ok = Oban.resume_queue(:control)

    assert_receive {:ok, 1}

    stop_supervised(Oban)
  end

  test "individual queues can be scaled" do
    start_supervised!({Oban, Keyword.put(@oban_opts, :queues, control: 1)})

    for ref <- 1..20, do: insert_job(ref: ref, sleep: 50)

    assert :ok = Oban.scale_queue(:control, 20)

    assert_receive {:ok, 20}

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
