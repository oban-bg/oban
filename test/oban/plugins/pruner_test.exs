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

    test "validating :only values" do
      assert {:error, _} = Pruner.validate(only: ["scheduled"])
      assert {:error, _} = Pruner.validate(only: ["completed", "scheduled"])
      assert :ok = Pruner.validate(only: ["completed", "cancelled"])
    end

    test "provides suggestions for :only values" do
      assert {:error,
              "Invalid status provided to :only option in pruner. Valid options are: completed, cancelled, discarded"} =
               Pruner.validate(only: ["completed", "scheduled"])
    end

    test "providing suggestions for unknown options" do
      assert {:error, "unknown option :inter, did you mean :interval?"} =
               Pruner.validate(inter: 1)
    end
  end

  describe "integration" do
    test "historic jobs are pruned when they are older than the configured age" do
      TelemetryHandler.attach_events()

      %Job{id: _id_} = insert!(%{}, state: "completed", scheduled_at: seconds_ago(61))
      %Job{id: _id_} = insert!(%{}, state: "cancelled", scheduled_at: seconds_ago(61))
      %Job{id: _id_} = insert!(%{}, state: "discarded", scheduled_at: seconds_ago(61))
      %Job{id: id_1} = insert!(%{}, state: "completed", scheduled_at: seconds_ago(59))

      start_supervised_oban!(plugins: [{Pruner, interval: 10, max_age: 60}])

      assert_receive {:event, :stop, _, %{plugin: Pruner} = meta}
      assert %{pruned_count: 3, pruned_jobs: [_ | _]} = meta

      assert [id_1] ==
               Job
               |> select([j], j.id)
               |> order_by(asc: :id)
               |> Repo.all()
    end

    test "only certain status pruned when specified in config" do
      TelemetryHandler.attach_events()

      %Job{id: _id_} = insert!(%{}, state: "completed", scheduled_at: seconds_ago(61))
      %Job{id: _id_} = insert!(%{}, state: "cancelled", scheduled_at: seconds_ago(61))
      %Job{id: id_1} = insert!(%{}, state: "discarded", scheduled_at: seconds_ago(61))

      start_supervised_oban!(
        plugins: [{Pruner, interval: 10, max_age: 60, only: ["completed", "cancelled"]}]
      )

      assert_receive {:event, :stop, _, %{plugin: Pruner} = meta}
      assert %{pruned_count: 2, pruned_jobs: [_ | _]} = meta

      assert [id_1] ==
               Job
               |> select([j], j.id)
               |> order_by(asc: :id)
               |> Repo.all()
    end
  end
end
