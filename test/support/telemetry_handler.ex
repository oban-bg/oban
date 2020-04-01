defmodule Oban.Test.TelemetryHandler do
  @moduledoc """
  Receives metrics and sends them to a process
  """

  def handle([:oban, :started], %{start_time: start_time}, meta, pid) do
    send(pid, {:executed, :started, start_time, meta})
  end

  def handle([:oban, event], %{duration: duration}, meta, pid) do
    send(pid, {:executed, event, duration, meta})
  end
end
