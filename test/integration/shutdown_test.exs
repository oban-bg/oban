defmodule Oban.Integration.ShutdownTest do
  use Oban.Case

  @moduletag :integration

  @oban_opts repo: Repo, queues: [alpha: 3]

  test "slow jobs are allowed to complete within the shutdown grace period" do
    start_supervised!({Oban, Keyword.put(@oban_opts, :shutdown_grace_period, 500)})

    %Job{id: id_1} = insert_job!(ref: 1, sleep: 10)
    %Job{id: id_2} = insert_job!(ref: 2, sleep: 4000)

    assert_receive {:ok, 1}

    :ok = stop_supervised(Oban)

    assert Repo.get(Job, id_1).state == "completed"
    assert Repo.get(Job, id_2).state == "executing"
  end

  # Orphaned jobs were started but never managed to finish. This is likely
  # because the job couldn't complete within the shutdown grace period.
  # Regardless, we want to start the job again and give it another chance to
  # finish.
  test "orphaned jobs are transitioned back to an available state" do
    start_supervised({Oban, Keyword.put(@oban_opts, :shutdown_grace_period, 50)})

    insert_job!(ref: 1, sleep: 1)
    insert_job!(ref: 2, sleep: 100)

    # By confirming that the first job completed we can be sure that the second
    # job had time to start.
    assert_receive {:ok, 1}
    refute_receive {:ok, 2}, 50

    :ok = stop_supervised(Oban)

    unlock_all()

    start_supervised({Oban, @oban_opts})

    assert_receive {:ok, 2}, 200
    refute_receive {:ok, 1}

    :ok = stop_supervised(Oban)
  end

  defp insert_job!(args) do
    args
    |> Worker.new(queue: "alpha")
    |> Repo.insert!()
  end

  defp unlock_all do
    Repo.query("SELECT pg_advisory_unlock_all()")
  end
end
