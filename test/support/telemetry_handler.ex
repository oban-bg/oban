defmodule Oban.TelemetryHandler do
  @moduledoc """
  This utility module is used during job tests to capture telemetry events
  and send them back to the test processes that registered the handler.
  """

  import ExUnit.Callbacks, only: [on_exit: 1]

  def attach_events do
    name = name()

    events = [
      [:oban, :job, :start],
      [:oban, :job, :stop],
      [:oban, :job, :exception],
      [:oban, :plugin, :start],
      [:oban, :plugin, :stop],
      [:oban, :plugin, :exception],
      [:oban, :supervisor, :init]
    ]

    on_exit(fn -> :telemetry.detach(name) end)

    :telemetry.attach_many(name, events, &handle/4, self())
  end

  def handle([:oban, :job, :start], %{system_time: start_time}, meta, pid) do
    send(pid, {:event, :start, start_time, meta})
  end

  def handle([:oban, :job, :stop], measure, meta, pid) do
    send(pid, {:event, :stop, measure, meta})
  end

  def handle([:oban, :job, event], %{duration: duration}, meta, pid) do
    send(pid, {:event, event, duration, meta})
  end

  def handle([:oban, :plugin, event], measurements, meta, pid) do
    send(pid, {:event, event, measurements, meta})
  end

  def handle(event, measurements, meta, pid) do
    send(pid, {:event, event, measurements, meta})
  end

  defp name, do: "handler-#{System.unique_integer([:positive])}"
end
