defmodule Oban.TelemetryHandler do
  @moduledoc """
  This utility module is used during job tests to capture telemetry events
  and send them back to the test processes that registered the handler.
  """

  import ExUnit.Callbacks, only: [on_exit: 1]

  @span_tail [:start, :stop, :exception]
  @span_type [
    :job,
    :plugin,
    [:engine, :insert_job],
    [:engine, :insert_all_jobs],
    [:engine, :fetch_jobs],
    [:peer, :election]
  ]

  def attach_events(opts \\ []) do
    span_tail = Keyword.get(opts, :span_tail, @span_tail)
    span_type = Keyword.get(opts, :span_type, @span_type)

    name = name()

    events =
      for type <- span_type, tail <- span_tail do
        List.flatten([:oban, type, tail])
      end

    events = [[:oban, :supervisor, :init] | events]

    on_exit(fn -> :telemetry.detach(name) end)

    :telemetry.attach_many(name, events, &handle/4, self())
  end

  def handle([:oban, :job, :start], %{system_time: start_time}, meta, pid) do
    send(pid, {:event, :start, start_time, meta})
  end

  def handle([:oban, :job, event], measure, meta, pid) do
    send(pid, {:event, event, measure, meta})
  end

  def handle([:oban, :engine | event], measure, meta, pid) do
    send(pid, {:event, event, measure, meta})
  end

  def handle([:oban, :plugin, event], measure, meta, pid) do
    send(pid, {:event, event, measure, meta})
  end

  def handle([:oban, :peer | event], measure, meta, pid) do
    send(pid, {:event, event, measure, meta})
  end

  def handle(event, measure, meta, pid) do
    send(pid, {:event, event, measure, meta})
  end

  defp name, do: "handler-#{System.unique_integer([:positive])}"
end
