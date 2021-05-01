defmodule Oban.Plugins.GossipTest do
  use Oban.Case

  alias Oban.Plugins.Gossip
  alias Oban.{Notifier, PluginTelemetryHandler}

  @moduletag :integration

  test "queue producers periodically emit check meta as gossip" do
    PluginTelemetryHandler.attach_plugin_events("plugin-gossip-handler")

    name =
      start_supervised_oban!(
        plugins: [{Gossip, interval: 10}],
        queues: [alpha: 2, omega: 3]
      )

    :ok = Notifier.listen(%Oban.Config{node: node(), repo: nil}, name, [:gossip])

    assert_receive {:notification, :gossip, %{"queue" => "alpha", "limit" => 2}}
    assert_receive {:notification, :gossip, %{"queue" => "omega", "limit" => 3}}

    assert_receive {:event, :start, %{system_time: _}, %{conf: _, plugin: Gossip}}
    assert_receive {:event, :stop, %{duration: _}, %{conf: _, plugin: Gossip, gossip_count: 2}}
  after
    :telemetry.detach("plugin-gossip-handler")
  end
end
