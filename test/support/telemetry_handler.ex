defmodule Oban.TelemetryHandler do
  @moduledoc """
  This utility module is used during job tests to capture telemetry events
  and send them back to the test processes that registered the handler.
  """

  def attach_events(name) do
    events = [
      [:oban, :job, :start],
      [:oban, :job, :stop],
      [:oban, :job, :exception],
      [:oban, :supervisor, :init]
    ]

    :telemetry.attach_many(name, events, &handle/4, self())
  end

  def handle([:oban, :job, :start], %{system_time: start_time}, meta, pid) do
    send(pid, {:event, :start, start_time, meta})
  end

  def handle([:oban, :job, :stop], event_measurements, meta, pid) do
    send(pid, {:event, :stop, event_measurements, meta})
  end

  def handle([:oban, :job, event], %{duration: duration}, meta, pid) do
    send(pid, {:event, event, duration, meta})
  end

  def handle([:oban, :supervisor, :init] = event, measurements, meta, pid) do
    send(pid, {:event, event, measurements, meta})
  end
end
