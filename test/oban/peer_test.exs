defmodule Oban.PeerTest do
  use Oban.Case

  import ExUnit.CaptureLog

  alias Oban.{Config, Peer, Registry}

  @moduletag :integration

  @opts [repo: Repo, name: Oban.PeerTest]

  test "only a single peer is leader" do
    conf = Config.new(@opts)

    assert [_leader] =
             [A, B, C]
             |> Enum.map(&start_supervised!({Peer, conf: conf, name: &1}))
             |> Enum.filter(&Peer.leader?/1)
  end

  test "leadership transfers to another peer when the leader exits" do
    conf = Config.new(@opts)

    peer_a = start_supervised!({Peer, conf: conf, interval: 20, name: Peer.A})

    Process.sleep(50)

    peer_b = start_supervised!({Peer, conf: conf, interval: 20, name: Peer.B})

    assert Peer.leader?(peer_a)

    stop_supervised(Peer.A)

    with_backoff([sleep: 10, total: 30], fn ->
      assert Peer.leader?(peer_b)
    end)
  end

  test "leadership is disabled along with plugins" do
    name = start_supervised_oban!(plugins: false)

    refute Registry.whereis(name, Peer)
  end

  test "gacefully handling a missing oban_peers table" do
    mangle_peers_table!()

    logged =
      capture_log(fn ->
        name = start_supervised_oban!(plugins: [])

        refute name
               |> Oban.config()
               |> Peer.leader?()
      end)

    assert logged =~ "leadership is disabled"
  after
    reform_peers_table!()
  end

  test "a single node acquires leadership" do
    name = start_supervised_oban!(plugins: [])

    assert name
           |> Oban.config()
           |> Peer.leader?()
  end

  defp mangle_peers_table! do
    Repo.query!("ALTER TABLE oban_peers RENAME TO oban_reeps")
  end

  defp reform_peers_table! do
    Repo.query!("ALTER TABLE oban_reeps RENAME TO oban_peers")
  end
end
