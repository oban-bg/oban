defmodule Oban.Plugins.ReindexerTest do
  use Oban.Case, async: true

  alias Oban.Plugins.Reindexer
  alias Oban.{PluginTelemetryHandler, Registry}

  describe "validate/1" do
    test "validating that schedule is a valid cron expression" do
      assert {:error, _} = Reindexer.validate(schedule: "-1 * * * *")

      assert :ok = Reindexer.validate(schedule: "0 0 * * *")
    end

    test "validating that :timezone is a known timezone" do
      assert {:error, _} = Reindexer.validate(timezone: "")
      assert {:error, _} = Reindexer.validate(timezone: nil)
      assert {:error, _} = Reindexer.validate(timezone: "america")
      assert {:error, _} = Reindexer.validate(timezone: "america/chicago")

      assert :ok = Reindexer.validate(timezone: "Etc/UTC")
      assert :ok = Reindexer.validate(timezone: "Europe/Copenhagen")
      assert :ok = Reindexer.validate(timezone: "America/Chicago")
    end
  end

  @tag :reindex
  test "reindexing according to the provided schedule" do
    PluginTelemetryHandler.attach_plugin_events("plugin-reindexer-handler")

    name = start_supervised_oban!(plugins: [{Reindexer, schedule: "* * * * *"}])

    name
    |> Registry.whereis({:plugin, Reindexer})
    |> send(:reindex)

    assert_receive {:event, :start, _, %{plugin: Reindexer}}, 1000
    assert_receive {:event, :stop, _, %{plugin: Reindexer}}, 1000

    stop_supervised(name)
  after
    :telemetry.detach("plugin-reindexer-handler")
  end
end
