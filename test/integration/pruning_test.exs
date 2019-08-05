defmodule Oban.Integration.PruningTest do
  use Oban.Case

  import Ecto.Query

  @moduletag :integration

  defmodule FakeWorker do
    use Oban.Worker, queue: :default

    @impl Worker
    def perform(_args, _job), do: :ok
  end

  test "historic jobs may be pruned based on a maximum rows count" do
    %Job{id: id_1} = insert_job!(state: "available")
    %Job{id: _id_} = insert_job!(state: "completed")
    %Job{id: _id_} = insert_job!(state: "discarded")
    %Job{id: id_4} = insert_job!(state: "executing")
    %Job{id: _id_} = insert_job!(state: "completed")
    %Job{id: id_6} = insert_job!(state: "completed")

    start_supervised!({Oban, repo: Repo, prune: {:maxlen, 1}, prune_interval: 10})

    with_backoff(fn ->
      assert retained_ids() == [id_1, id_4, id_6]
    end)

    :ok = stop_supervised(Oban)
  end

  test "historic jobs may be be pruned based on a maximum age in seconds" do
    %Job{id: _id_} = insert_job!(state: "completed", completed_at: minutes_ago(6))
    %Job{id: _id_} = insert_job!(state: "completed", completed_at: minutes_ago(5))
    %Job{id: id_1} = insert_job!(state: "completed", completed_at: minutes_ago(3))
    %Job{id: id_2} = insert_job!(state: "completed", completed_at: minutes_ago(1))

    start_supervised!({Oban, repo: Repo, prune: {:maxage, 60 * 4}, prune_interval: 10})

    with_backoff(fn ->
      assert retained_ids() == [id_1, id_2]
    end)

    :ok = stop_supervised(Oban)
  end

  defp insert_job!(opts) do
    %{}
    |> FakeWorker.new(opts)
    |> Repo.insert!()
  end

  defp retained_ids do
    Job
    |> select([j], j.id)
    |> order_by(asc: :id)
    |> Repo.all()
  end

  defp minutes_ago(minutes) do
    DateTime.add(DateTime.utc_now(), minutes * 60 * -1)
  end
end
