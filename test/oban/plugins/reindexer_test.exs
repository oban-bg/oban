defmodule Oban.Plugins.ReindexerTest do
  use Oban.Case, async: true

  alias Oban.Plugins.Reindexer
  alias Oban.{PluginTelemetryHandler, Registry}

  setup do
    PluginTelemetryHandler.attach_plugin_events("plugin-reindexer-handler")

    on_exit(fn ->
      :telemetry.detach("plugin-reindexer-handler")
    end)
  end

  test "reindexing according to the provided schedule" do
    name = start_supervised_oban!(plugins: [{Reindexer, schedule: "* * * * *"}])

    name
    |> Registry.whereis({:plugin, Reindexer})
    |> send(:reindex)

    assert_receive {:event, :start, %{system_time: _}, %{conf: _, plugin: Reindexer}}
    assert_receive {:event, :stop, %{duration: _}, %{conf: _, plugin: Reindexer}}

    stop_supervised(name)
  end
end
