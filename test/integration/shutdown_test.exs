defmodule Oban.Integration.ShutdownTest do
  use Oban.Case, async: true

  test "slow jobs are allowed to complete within the shutdown grace period" do
    name =
      start_supervised_oban!(poll_interval: 10, queues: [alpha: 3], shutdown_grace_period: 50)

    %Job{id: id_1} = insert!(ref: 1, sleep: 10)
    %Job{id: id_2} = insert!(ref: 2, sleep: 4000)

    assert_receive {:ok, 1}
    refute_receive {:ok, 2}, 100

    :ok = stop_supervised(name)

    assert Repo.get(Job, id_1).state == "completed"
    assert Repo.get(Job, id_2).state == "executing"
  end

  test "additional jobs aren't started after shutdown starts" do
    name =
      start_supervised_oban!(poll_interval: 10, queues: [alpha: 1], shutdown_grace_period: 10)

    %Job{id: id_1} = insert!(ref: 1, sleep: 50)
    %Job{id: id_2} = insert!(ref: 2, sleep: 1)
    %Job{id: id_3} = insert!(ref: 2, sleep: 1)

    assert_receive {:started, 1}

    :ok = stop_supervised(name)

    refute_receive {:started, 2}, 100
    refute_receive {:started, 3}, 100

    assert Repo.get(Job, id_1).state == "executing"
    assert Repo.get(Job, id_2).state == "available"
    assert Repo.get(Job, id_3).state == "available"
  end
end
