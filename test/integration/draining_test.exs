defmodule Oban.Integration.DrainingTest do
  use Oban.Case

  @moduletag :integration

  @oban_opts repo: Repo, queues: false

  test "all jobs in a queue can be drained and executed synchronously" do
    start_supervised!({Oban, @oban_opts})

    insert_job!(ref: 1, action: "OK")
    insert_job!(ref: 2, action: "FAIL")
    insert_job!(ref: 3, action: "OK")

    assert 3 == Oban.drain_queue(:draining)

    assert_received {:ok, 3}
    assert_received {:fail, 2}
    assert_received {:ok, 1}

    stop_supervised(Oban)
  end

  defp insert_job!(args) do
    args
    |> Map.new()
    |> Map.put(:bin_pid, Worker.pid_to_bin())
    |> Job.new(worker: Worker, queue: :draining)
    |> Repo.insert!()
  end
end
