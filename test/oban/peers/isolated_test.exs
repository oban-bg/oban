defmodule Oban.Peers.IsolatedTest do
  use Oban.Case, async: true

  describe "get_leader/2" do
    test "returning the current node only when leader" do
      name = start_supervised_oban!(peer: {Oban.Peers.Isolated, leader?: false})

      refute Oban.Peer.leader?(name)
      refute Oban.Peer.get_leader(name)

      name = start_supervised_oban!(peer: {Oban.Peers.Isolated, leader?: true})

      assert Oban.Peer.leader?(name)
      assert Oban.Peer.get_leader(name)
    end
  end
end
