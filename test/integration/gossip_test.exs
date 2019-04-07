defmodule Oban.Integration.GossipTest do
  use Oban.Case

  alias Oban.Notifier

  @moduletag :integration

  @oban_opts node: "oban.test", poll_interval: 50, repo: Repo, queues: [alpha: 5, gamma: 8]

  test "queue producers broadcast runtime statistics" do
    insert_job!(ref: 1, sleep: 500, queue: "alpha")
    insert_job!(ref: 2, sleep: 500, queue: "alpha")

    start_supervised!({Oban, @oban_opts})

    :ok = Notifier.listen("oban_gossip")

    assert_gossip(%{
      "count" => 2,
      "limit" => 5,
      "node" => "oban.test",
      "paused" => false,
      "queue" => "alpha"
    })

    assert_gossip(%{
      "count" => 0,
      "limit" => 8,
      "node" => "oban.test",
      "paused" => false,
      "queue" => "gamma"
    })

    stop_supervised(Oban)
  end

  defp assert_gossip(message) do
    assert_receive {:notification, _, _, "oban_gossip", payload}
    assert {:ok, decoded} = Jason.decode(payload)
    assert message == decoded
  end

  defp insert_job!(args) do
    args
    |> Map.new()
    |> Map.put(:bin_pid, Worker.pid_to_bin())
    |> Job.new(worker: Worker, queue: args[:queue])
    |> Repo.insert!()
  end
end
