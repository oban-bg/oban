defmodule Oban.Integration.PulseTest do
  use Oban.Case

  alias Oban.Beat

  import Ecto.Query

  @moduletag :integration

  @oban_opts node: "oban.test", poll_interval: 50, repo: Repo, queues: [alpha: 5, gamma: 3]

  test "queue producers record runtime information in beat records" do
    %Job{id: jid1} = insert_job!(ref: 1, sleep: 500, queue: :alpha)
    %Job{id: jid2} = insert_job!(ref: 2, sleep: 500, queue: :alpha)
    %Job{id: jid3} = insert_job!(ref: 3, sleep: 500, queue: :gamma)

    start_supervised!({Oban, @oban_opts})

    with_backoff(fn ->
      assert {:ok, beat} = fetch_beat(node: "oban.test", queue: "alpha")

      assert beat.limit == 5
      refute beat.paused
      assert Enum.sort(beat.running) == Enum.sort([jid2, jid1])

      assert {:ok, beat} = fetch_beat(node: "oban.test", queue: "gamma")

      assert beat.limit == 3
      refute beat.paused
      assert beat.running == [jid3]
    end)

    stop_supervised(Oban)
  end

  defp insert_job!(args) do
    args
    |> Worker.new(queue: args[:queue])
    |> Repo.insert!()
  end

  defp fetch_beat(fields) do
    Beat
    |> where(^fields)
    |> limit(1)
    |> Repo.one()
    |> case do
      nil -> :error
      beat -> {:ok, beat}
    end
  end
end
