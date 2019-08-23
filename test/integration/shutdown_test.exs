defmodule Oban.Integration.ShutdownTest do
  use Oban.Case

  @moduletag :integration

  test "slow jobs are allowed to complete within the shutdown grace period" do
    start_supervised({Oban, repo: Repo, queues: [alpha: 3], shutdown_grace_period: 50})

    %Job{id: id_1} = insert_job!(ref: 1, sleep: 10)
    %Job{id: id_2} = insert_job!(ref: 2, sleep: 4000)

    assert_receive {:ok, 1}
    refute_receive {:ok, 2}, 100

    :ok = stop_supervised(Oban)

    assert Repo.get(Job, id_1).state == "completed"
    assert Repo.get(Job, id_2).state == "executing"
  end

  defp insert_job!(args) do
    args
    |> Worker.new(queue: "alpha")
    |> Repo.insert!()
  end
end
