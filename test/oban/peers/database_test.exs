defmodule Oban.Peers.DatabaseTest do
  use Oban.Case

  import ExUnit.CaptureLog

  alias Oban.Peer
  alias Oban.Peers.Database
  alias Oban.TelemetryHandler
  alias Oban.Test.DolphinRepo

  test "enforcing a single leader with the Basic engine" do
    name = start_supervised_oban!(peer: false)
    conf = Oban.config(name)

    assert [_leader] =
             [A, B, C]
             |> Enum.map(&start_supervised_peer!(conf, &1))
             |> Enum.filter(&Database.leader?/1)
  end

  @tag :dolphin
  test "enforcing a single leader with the Dolphin engine" do
    name = start_supervised_oban!(engine: Oban.Engines.Dolphin, peer: false, repo: DolphinRepo)
    conf = Oban.config(name)

    assert [_leader] =
             [A, B, C]
             |> Enum.map(&start_supervised_peer!(conf, &1))
             |> Enum.filter(&Database.leader?/1)
  end

  defp start_supervised_peer!(conf, name) do
    node = "web.#{name}"
    conf = %{conf | node: node, peer: {Database, []}}

    start_supervised!({Peer, conf: conf, name: name})
  end

  test "dispatching leadership election events" do
    TelemetryHandler.attach_events()

    start_supervised_oban!(peer: Database)

    assert_receive {:event, [:election, :start], _measure,
                    %{leader: false, peer: Database, was_leader: nil}}

    assert_receive {:event, [:election, :stop], _measure,
                    %{leader: true, peer: Database, was_leader: false}}
  end

  test "gracefully handling a missing oban_peers table" do
    mangle_peers_table!()

    logged =
      capture_log(fn ->
        name = start_supervised_oban!(peer: Database)
        conf = Oban.config(name)

        start_supervised!({Peer, conf: conf, name: Peer})

        refute Database.leader?(Peer)
      end)

    assert logged =~ "leadership is disabled"
  after
    reform_peers_table!()
  end

  defp mangle_peers_table! do
    Repo.query!("ALTER TABLE oban_peers RENAME TO oban_reeps")
  end

  defp reform_peers_table! do
    Repo.query!("ALTER TABLE oban_reeps RENAME TO oban_peers")
  end
end
