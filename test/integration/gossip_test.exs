defmodule Oban.Integration.GossipTest do
  use Oban.Case

  import ExUnit.CaptureLog

  alias Oban.Notifier

  @moduletag :integration

  @oban_opts node: "oban.test", poll_interval: 50, repo: Repo, queues: [alpha: 5], verbose: false

  test "queue producers broadcast runtime statistics" do
    insert_job!(ref: 1, sleep: 500, queue: "alpha")
    insert_job!(ref: 2, sleep: 500, queue: "alpha")

    start_supervised!({Oban, @oban_opts})

    :ok = Notifier.listen(Oban.Notifier, "public", :gossip)

    assert_gossip(%{
      "count" => 2,
      "limit" => 5,
      "node" => "oban.test",
      "paused" => false,
      "queue" => "alpha"
    })

    stop_supervised(Oban)
  end

  test "broadcasts are silenced when :verbose mode is disabled" do
    insert_job!(ref: 1, sleep: 500, queue: "alpha")

    Logger.configure(level: :debug)

    logged =
      capture_log(fn ->
        start_supervised!({Oban, @oban_opts})

        :ok = Notifier.listen(Oban.Notifier, "public", :gossip)

        stop_supervised(Oban)
      end)

    refute logged =~ ~s(SELECT pg_notify)
    refute logged =~ ~s(UPDATE "oban_jobs")
  after
    Logger.configure(level: :warn)
  end

  defp assert_gossip(message) do
    assert_receive {:notification, _, _, "public.oban_gossip", payload}
    assert {:ok, decoded} = Jason.decode(payload)
    assert message == decoded
  end

  defp insert_job!(args) do
    args
    |> Worker.new(queue: args[:queue])
    |> Repo.insert!()
  end
end
