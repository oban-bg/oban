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

  test "historic beats are pruned beyond a fixed age" do
    insert_beat!(inserted_at: minutes_ago(1))
    insert_beat!(inserted_at: minutes_ago(59))
    insert_beat!(inserted_at: minutes_ago(60))
    insert_beat!(inserted_at: minutes_ago(70))
    insert_beat!(inserted_at: minutes_ago(120))

    # The `prune` value must not be :disabled, but the value doesn't matter
    start_supervised!(
      {Oban, repo: Repo, prune: {:maxage, 60 * 4}, prune_interval: 10, prune_limit: 1}
    )

    with_backoff(fn ->
      assert retained_beat_count() == 2
    end)

    :ok = stop_supervised(Oban)
  end

  defp insert_job!(opts) do
    %{}
    |> FakeWorker.new(opts)
    |> Repo.insert!()
  end

  @fake_beat_opts %{
    node: "fake.beat",
    nonce: "a1b2c3def4",
    queue: "alpha",
    limit: 1,
    started_at: DateTime.utc_now()
  }

  defp insert_beat!(opts) do
    opts
    |> Map.new()
    |> Map.merge(@fake_beat_opts)
    |> Beat.new()
    |> Repo.insert!()
  end

  defp retained_ids do
    Job
    |> select([j], j.id)
    |> order_by(asc: :id)
    |> Repo.all()
  end

  defp retained_beat_count do
    Repo.one(from b in Beat, select: count())
  end

  defp minutes_ago(minutes) do
    DateTime.add(DateTime.utc_now(), minutes * -60)
  end
end
