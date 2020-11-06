defmodule Oban.Integration.PruningTest do
  use Oban.Case

  import Ecto.Query

  @moduletag :integration

  defmodule FakeWorker do
    use Oban.Worker, queue: :default

    @impl Worker
    def perform(_job), do: :ok
  end

  test "historic jobs are pruned when they are older than the configured age" do
    %Job{id: _id_} = insert!(%{}, state: "completed", attempted_at: seconds_ago(62))
    %Job{id: _id_} = insert!(%{}, state: "completed", attempted_at: seconds_ago(61))
    %Job{id: _id_} = insert!(%{}, state: "cancelled", attempted_at: seconds_ago(61))
    %Job{id: _id_} = insert!(%{}, state: "discarded", attempted_at: seconds_ago(61))
    %Job{id: id_1} = insert!(%{}, state: "completed", attempted_at: seconds_ago(59))
    %Job{id: id_2} = insert!(%{}, state: "completed", attempted_at: seconds_ago(10))

    start_supervised_oban!(plugins: [{Oban.Plugins.Pruner, interval: 10, max_age: 60}])

    with_backoff(fn ->
      assert retained_ids() == [id_1, id_2]
    end)
  end

  defp retained_ids do
    Job
    |> select([j], j.id)
    |> order_by(asc: :id)
    |> Repo.all()
  end
end
