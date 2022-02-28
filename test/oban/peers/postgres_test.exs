defmodule Oban.Peers.PostgresTest do
  use Oban.Case

  import ExUnit.CaptureLog

  alias Oban.Peer
  alias Oban.Peers.Postgres

  test "only a single peer is leader" do
    name = start_supervised_oban!(peer: Postgres, plugins: false)
    conf = Oban.config(name)

    assert [_leader] =
             [A, B, C]
             |> Enum.map(&start_supervised!({Peer, conf: conf, name: &1}))
             |> Enum.filter(&Postgres.leader?/1)
  end

  test "gacefully handling a missing oban_peers table" do
    mangle_peers_table!()

    logged =
      capture_log(fn ->
        name = start_supervised_oban!(peer: Postgres, plugins: [])

        refute Peer.leader?(name)
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
