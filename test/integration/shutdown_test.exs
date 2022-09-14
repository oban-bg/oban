defmodule Oban.Integration.ShutdownTest do
  use Oban.Case

  @opts [
    poll_interval: 10,
    queues: [alpha: 1],
    shutdown_grace_period: 50
  ]

  test "slow jobs are allowed to complete within the shutdown grace period" do
    %Job{id: id_1} = insert!(ref: 1, sleep: 5)
    %Job{id: id_2} = insert!(ref: 2, sleep: 5000)

    name = start_supervised_oban!(@opts)

    assert_receive {:started, 1}
    assert_receive {:started, 2}

    :ok = stop_supervised(name)

    assert_receive {:ok, 1}
    refute_receive {:ok, 2}, 50

    assert Repo.get(Job, id_1).state == "completed"
    assert Repo.get(Job, id_2).state == "executing"
  end

  test "additional jobs aren't started after shutdown starts" do
    %Job{id: id_1} = insert!(ref: 1, sleep: 40)
    %Job{id: id_2} = insert!(ref: 2, sleep: 1)

    name = start_supervised_oban!(@opts)

    assert_receive {:started, 1}

    :ok = stop_supervised(name)

    refute_receive {:started, 2}, 50

    assert Repo.get(Job, id_1).state == "completed"
    assert Repo.get(Job, id_2).state == "available"
  end
end
