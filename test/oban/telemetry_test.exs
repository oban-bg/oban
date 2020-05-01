defmodule Oban.TelemetryTest do
  use ExUnit.Case, async: true

  alias Oban.Telemetry

  defmodule Handler do
    def handle_event(event, timing, meta, pid) do
      send(pid, {event, timing, meta})
    end
  end

  describe "span/3" do
    test "tracing function execution with start/stop events" do
      events = [[:oban, :rand, :start], [:oban, :rand, :stop]]

      :telemetry.attach_many("oban-rand", events, &Handler.handle_event/4, self())

      result = Telemetry.span(:rand, &:rand.uniform/0, %{extra: true})

      assert_receive {[:oban, :rand, :start], %{system_time: system_time}, %{extra: true}}
      assert_receive {[:oban, :rand, :stop], %{duration: duration}, %{extra: true}}

      assert is_float(result)
      assert is_integer(system_time)
      assert is_integer(duration)

      assert system_time > 0
      assert duration > 0
    after
      :telemetry.detach("oban-rand")
    end

    test "tracing function execution with an exception" do
      events = [[:oban, :rand, :start], [:oban, :rand, :exception]]

      :telemetry.attach_many("oban-boom", events, &Handler.handle_event/4, self())

      assert_raise RuntimeError, fn ->
        Telemetry.span(:rand, fn -> raise "boom" end, %{extra: true})
      end

      assert_receive {[:oban, :rand, :start], _timing, _meta}
      assert_receive {[:oban, :rand, :exception], %{duration: duration}, meta}

      assert is_integer(duration)

      assert %{kind: :error, reason: reason, stacktrace: stacktrace} = meta
      assert %RuntimeError{message: "boom"} = reason
      assert [_ | _] = stacktrace
    after
      :telemetry.detach("oban-boom")
    end
  end
end
