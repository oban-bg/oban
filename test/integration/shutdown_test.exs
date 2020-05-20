defmodule Oban.Integration.ShutdownTest do
  use Oban.Case

  @moduletag :integration

  test "slow jobs are allowed to complete within the shutdown grace period" do
    start_supervised_oban!(queues: [alpha: 3], shutdown_grace_period: 50)

    %Job{id: id_1} = insert!(ref: 1, sleep: 10)
    %Job{id: id_2} = insert!(ref: 2, sleep: 4000)

    assert_receive {:ok, 1}
    refute_receive {:ok, 2}, 100

    :ok = stop_supervised(Oban)

    assert Repo.get(Job, id_1).state == "completed"
    assert Repo.get(Job, id_2).state == "executing"
  end
end
