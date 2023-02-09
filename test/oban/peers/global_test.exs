defmodule Oban.Peers.GlobalTest do
  use Oban.Case, async: true

  alias Oban.Peer
  alias Oban.Peers.Global
  alias Oban.TelemetryHandler

  test "only a single peer is leader" do
    TelemetryHandler.attach_events()

    name_1 = start_supervised_oban!(peer: Global, node: "worker.1")
    name_2 = start_supervised_oban!(peer: Global, node: "worker.2")

    conf_1 = %{Oban.config(name_1) | name: Oban}
    conf_2 = %{Oban.config(name_2) | name: Oban}

    peer_1 = start_supervised!({Peer, conf: conf_1, name: A})
    peer_2 = start_supervised!({Peer, conf: conf_2, name: B})

    assert [_leader] = Enum.filter([peer_1, peer_2], &Global.leader?/1)

    assert_receive {:event, [:election, :start], _measure, %{leader: _, peer: Oban.Peers.Global}}
    assert_receive {:event, [:election, :stop], _measure, %{leader: _, peer: Oban.Peers.Global}}
  end
end
