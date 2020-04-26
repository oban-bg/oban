defmodule Oban.Integration.PruningTest do
  use Oban.Case

  import Ecto.Query

  @moduletag :integration

  defmodule FakeWorker do
    use Oban.Worker, queue: :default

    @impl Worker
    def perform(_args, _job), do: :ok
  end

  test "historic jobs are pruned when they are older than 60 seconds" do
    %Job{id: _id_} = insert_job!(state: "completed", attempted_at: seconds_ago(62))
    %Job{id: _id_} = insert_job!(state: "completed", attempted_at: seconds_ago(61))
    %Job{id: id_1} = insert_job!(state: "completed", attempted_at: seconds_ago(59))
    %Job{id: id_2} = insert_job!(state: "completed", attempted_at: seconds_ago(10))

    start_supervised!({Oban, repo: Repo, plugins: [{Oban.Plugins.FixedPruner, interval: 10}]})

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
end
