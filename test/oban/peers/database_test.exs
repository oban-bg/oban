defmodule Oban.Peers.DatabaseTest do
  use Oban.Case, async: true

  import Ecto.Query, only: [where: 2]

  alias Oban.Peer
  alias Oban.Peers.Database
  alias Oban.TelemetryHandler
  alias Oban.Test.DolphinRepo

  test "enforcing a single leader with the Basic engine" do
    name = start_supervised_oban!(peer: false)
    conf = Oban.config(name)

    assert [_leader] =
             [Peer.DB.A, Peer.DB.B, Peer.DB.C]
             |> Enum.map(&start_supervised_peer!(conf, &1))
             |> Enum.filter(&Database.leader?/1)
  end

  @tag :dolphin
  test "enforcing a single leader with the Dolphin engine" do
    name = start_supervised_oban!(engine: Oban.Engines.Dolphin, peer: false, repo: DolphinRepo)
    conf = Oban.config(name)

    assert [_leader] =
             [Peer.DB.A, Peer.DB.B, Peer.DB.C]
             |> Enum.map(&start_supervised_peer!(conf, &1))
             |> Enum.filter(&Database.leader?/1)
  end

  test "retaining leadership while the lease is held" do
    name = start_supervised_oban!(peer: false)
    conf = Oban.config(name)

    peer = start_supervised_peer!(conf, Peer.DB.A)

    assert Database.leader?(peer)

    GenServer.call(peer, :election)

    assert Database.leader?(peer)
  end

  test "conceding leadership after another node takes over the lease" do
    name = start_supervised_oban!(peer: false)
    conf = Oban.config(name)
    peer = start_supervised_peer!(conf, Peer.DB.A)

    assert Database.leader?(peer)

    take_over(conf, expires_at: seconds_from_now(30))

    GenServer.call(peer, :election)

    refute Database.leader?(peer)
    assert "web.B" == Database.get_leader(peer)
  end

  test "assuming leadership after another node's lease expires" do
    name = start_supervised_oban!(peer: false)
    conf = Oban.config(name)
    peer = start_supervised_peer!(conf, Peer.DB.A)

    assert Database.leader?(peer)

    take_over(conf, expires_at: seconds_from_now(-1))

    GenServer.call(peer, :election)

    assert Database.leader?(peer)
  end

  test "dispatching leadership election events" do
    TelemetryHandler.attach_events()

    start_supervised_oban!(peer: Database)

    assert_receive {:event, [:election, :start], _measure,
                    %{leader: false, peer: Database, was_leader: nil}}

    assert_receive {:event, [:election, :stop], _measure,
                    %{leader: true, peer: Database, was_leader: false}}
  end

  defp start_supervised_peer!(conf, name) do
    node = "web.#{name}"
    conf = %{conf | node: node, peer: {Database, []}}

    start_supervised!({Peer, conf: conf, name: name})
  end

  # Slightly invasive, but much easier than coordinating multiple supervised instances.
  defp take_over(conf, expires_at: expires_at) do
    "oban_peers"
    |> where(name: ^inspect(conf.name))
    |> Repo.update_all(set: [node: "web.B", expires_at: expires_at])
  end
end
