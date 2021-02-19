defmodule Oban.Plugins.RepeaterTest do
  use Oban.Case, async: true

  alias Oban.Plugins.Repeater
  alias Oban.{PluginTelemetryHandler, Registry}

  defmodule RepeaterRelay do
    use GenServer

    def start_link(name: name, test: test) do
      GenServer.start_link(__MODULE__, test, name: name)
    end

    @impl true
    def init(test) do
      {:ok, test}
    end

    @impl true
    def handle_info({:notification, _, _} = message, test) do
      send(test, message)

      {:noreply, test}
    end
  end

  test "broadcasting insert messages to producers to trigger dispatch" do
    PluginTelemetryHandler.attach_plugin_events("plugin-repeater-handler")

    oban_name = start_supervised_oban!(plugins: [{Repeater, interval: 10}])
    prod_name = Registry.via(oban_name, {:producer, "default"})

    start_supervised({RepeaterRelay, name: prod_name, test: self()})

    assert_receive {:notification, :insert, %{"queue" => "default"}}

    assert_receive {:event, :start, %{system_time: _}, %{conf: _, plugin: Repeater}}
    assert_receive {:event, :stop, %{duration: _}, %{conf: _, plugin: Repeater}}
  after
    :telemetry.detach("plugin-repeater-handler")
  end
end
