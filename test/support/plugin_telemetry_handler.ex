defmodule Oban.PluginTelemetryHandler do
  @moduledoc """
  This utility module is used during plugin tests to capture telemetry events
  and send them back to the test processes that registered the handler.
  """

  def attach_plugin_events(name) do
    events = [
      [:oban, :plugin, :start],
      [:oban, :plugin, :stop],
      [:oban, :plugin, :exception]
    ]

    :telemetry.attach_many(name, events, &handle/4, self())
  end

  def handle([:oban, :plugin, :start], measurements, meta, pid) do
    send(pid, {:event, :start, measurements, meta})
  end

  def handle([:oban, :plugin, :stop], measurements, meta, pid) do
    send(pid, {:event, :stop, measurements, meta})
  end

  def handle([:oban, :plugin, :exception], measurements, meta, pid) do
    send(pid, {:event, :exception, measurements, meta})
  end
end
