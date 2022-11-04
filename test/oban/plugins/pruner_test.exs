defmodule Oban.Plugins.PrunerTest do
  use Oban.Case, async: true

  import Ecto.Query

  alias Oban.Plugins.Pruner
  alias Oban.TelemetryHandler

  describe "validate/1" do
    test "validating numerical values" do
      assert {:error, _} = Pruner.validate(interval: 0)
      assert {:error, _} = Pruner.validate(max_age: 0)
      assert {:error, _} = Pruner.validate(limit: 0)

      assert :ok = Pruner.validate(interval: :timer.seconds(30))
      assert :ok = Pruner.validate(max_age: 60)
      assert :ok = Pruner.validate(limit: 1_000)
    end
  end

  describe "integration" do
    test "historic jobs are pruned when they are older than the configured age" do
      TelemetryHandler.attach_events()

      %Job{id: _id_} = insert!(%{}, state: "completed", attempted_at: seconds_ago(62))
      %Job{id: _id_} = insert!(%{}, state: "completed", attempted_at: seconds_ago(61))
      %Job{id: _id_} = insert!(%{}, state: "cancelled", cancelled_at: seconds_ago(61))
      %Job{id: _id_} = insert!(%{}, state: "discarded", discarded_at: seconds_ago(61))
      %Job{id: id_1} = insert!(%{}, state: "completed", attempted_at: seconds_ago(59))
      %Job{id: id_2} = insert!(%{}, state: "completed", attempted_at: seconds_ago(10))

      name = start_supervised_oban!(plugins: [{Pruner, interval: 10, max_age: 60}])

      with_backoff(fn -> assert retained_ids() == [id_1, id_2] end)

      assert_receive {:event, :start, %{system_time: _}, %{conf: _, plugin: Pruner}}
      assert_receive {:event, :stop, %{duration: _}, %{plugin: Pruner} = meta}

      assert %{pruned_count: 4, pruned_jobs: [_ | _] = jobs} = meta

      for %{state: state} <- jobs do
        assert state in ~w(cancelled completed discarded)
      end

      stop_supervised(name)
    end
  end

  defp retained_ids do
    Job
    |> select([j], j.id)
    |> order_by(asc: :id)
    |> Repo.all()
  end
end
