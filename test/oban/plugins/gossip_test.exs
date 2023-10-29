defmodule Oban.Plugins.GossipTest do
  use Oban.Case, async: true

  import ExUnit.CaptureLog

  test "ignoring plugin startup" do
    assert capture_log(fn ->
             start_supervised_oban!(plugins: [Oban.Plugins.Gossip])
           end) =~ "Gossip is deprecated"
  end
end
