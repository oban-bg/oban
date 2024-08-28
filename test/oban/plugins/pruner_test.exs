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

    test "providing suggestions for unknown options" do
      assert {:error, "unknown option :inter, did you mean :interval?"} =
               Pruner.validate(inter: 1)
    end
  end

  describe "integration" do
    test "historic jobs are pruned when they are older than the configured age" do
      TelemetryHandler.attach_events()

      %Job{id: _id_} = insert_historical("cancelled", :cancelled_at, 61, 61)
      %Job{id: _id_} = insert_historical("cancelled", :cancelled_at, 61, 59)
      %Job{id: _id_} = insert_historical("discarded", :discarded_at, 61, 61)
      %Job{id: _id_} = insert_historical("discarded", :discarded_at, 61, 59)
      %Job{id: _id_} = insert_historical("completed", :completed_at, 61, 61)
      %Job{id: _id_} = insert_historical("completed", :completed_at, 59, 61)

      %Job{id: id_1} = insert_historical("cancelled", :cancelled_at, 59, 61)
      %Job{id: id_2} = insert_historical("cancelled", :cancelled_at, 59, 59)
      %Job{id: id_3} = insert_historical("discarded", :discarded_at, 59, 61)
      %Job{id: id_4} = insert_historical("discarded", :discarded_at, 59, 59)
      %Job{id: id_5} = insert_historical("completed", :completed_at, 59, 59)
      %Job{id: id_6} = insert_historical("completed", :completed_at, 61, 59)

      start_supervised_oban!(plugins: [{Pruner, interval: 10, max_age: 60}])

      assert_receive {:event, :stop, _, %{plugin: Pruner} = meta}
      assert %{pruned_count: 6, pruned_jobs: [_ | _]} = meta

      assert [id_1, id_2, id_3, id_4, id_5, id_6] ==
               Job
               |> select([j], j.id)
               |> order_by(asc: :id)
               |> Repo.all()
    end
  end
end
