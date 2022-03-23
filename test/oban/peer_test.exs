defmodule Oban.PeerTest do
  use Oban.Case

  alias Oban.{Peer, Registry}

  @moduletag :integration

  describe "configuration" do
    test "leadership is disabled when peer is false" do
      name = start_supervised_oban!(peer: false)

      refute Registry.whereis(name, Peer)
      refute Peer.leader?(name)
    end

    test "leadership is disabled along with plugins" do
      name = start_supervised_oban!(plugins: false)

      refute Registry.whereis(name, Peer)
      refute Peer.leader?(name)
    end
  end

  for peer <- [Oban.Peers.Global, Oban.Peers.Postgres] do
    @peer peer

    describe "using #{peer}" do
      test "a single node acquires leadership" do
        name = start_supervised_oban!(peer: @peer)

        assert Peer.leader?(name)
      end

      test "leadership transfers to another peer when the leader exits" do
        name = start_supervised_oban!(peer: @peer, plugins: false)
        conf = Oban.config(name)

        peer_a = start_supervised!({Peer, conf: conf, name: Peer.A})

        Process.sleep(50)

        peer_b = start_supervised!({Peer, conf: conf, name: Peer.B})

        assert @peer.leader?(peer_a)

        stop_supervised(Peer.A)

        with_backoff([sleep: 10, total: 30], fn ->
          assert @peer.leader?(peer_b)
        end)
      end
    end
  end
end
