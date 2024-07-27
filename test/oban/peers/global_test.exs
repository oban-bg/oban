defmodule Oban.Peers.GlobalTest do
  use Oban.Case, async: true

  alias Oban.Peer
  alias Oban.Peers.Global
  alias Oban.TelemetryHandler

  test "only a single peer is leader" do
    # Start an instance just to provide a notifier under the Oban name
    start_supervised_oban!(name: Oban, peer: false)

    name_1 = start_supervised_oban!(peer: Global, node: "worker.1")
    name_2 = start_supervised_oban!(peer: Global, node: "worker.2")

    conf_1 = %{Oban.config(name_1) | name: Oban}
    conf_2 = %{Oban.config(name_2) | name: Oban}

    peer_1 = start_supervised!({Peer, conf: conf_1, name: A})
    peer_2 = start_supervised!({Peer, conf: conf_2, name: B})

    assert [_pid] = Enum.filter([peer_1, peer_2], &Global.leader?/1)
  end

  test "leadership changes when a peer terminates" do
    start_supervised_oban!(name: Oban, peer: false)

    :ok = Oban.Notifier.listen(Oban, :leader)

    conf =
      [peer: false, node: "worker.1"]
      |> start_supervised_oban!()
      |> Oban.config()
      |> Map.put(:peer, {Global, []})

    peer_1 = start_supervised!({Peer, name: A, conf: %{conf | name: Oban, node: "web.1"}})
    peer_2 = start_supervised!({Peer, name: B, conf: %{conf | name: Oban, node: "web.2"}})

    {leader, name} =
      Enum.find([{peer_1, A}, {peer_2, B}], fn {pid, _name} ->
        Global.leader?(pid)
      end)

    stop_supervised!(name)

    assert_receive {:notification, :leader, %{"down" => _}}

    with_backoff(fn ->
      assert Enum.find([peer_1, peer_2] -- [leader], &Global.leader?/1)
    end)
  end

  test "emitting telemetry events for elections" do
    TelemetryHandler.attach_events()

    start_supervised_oban!(peer: Global, node: "worker.1")

    assert_receive {:event, [:election, :start], _measure, %{leader: _, peer: Oban.Peers.Global}}
    assert_receive {:event, [:election, :stop], _measure, %{leader: _, peer: Oban.Peers.Global}}
  end
end
