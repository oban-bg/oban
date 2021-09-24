defmodule Oban.Integration.TelemetryTest do
  use Oban.Case

  import ExUnit.CaptureLog

  alias Oban.{Config, PerformError, Telemetry, TelemetryHandler}

  @moduletag :integration

  test "telemetry event is emitted for supervisor initialization" do
    TelemetryHandler.attach_events("init-handler")

    name = start_supervised_oban!(queues: [alpha: 2])
    pid = Oban.Registry.whereis(name)
    conf = Oban.config(name)

    assert_receive {:event, [:oban, :supervisor, :init], %{system_time: _},
                    %{conf: ^conf, pid: ^pid}}
  after
    :telemetry.detach("init-handler")
  end

  test "telemetry events are emitted for executed jobs" do
    TelemetryHandler.attach_events("job-handler")

    name = start_supervised_oban!(queues: [alpha: 2])

    %Job{id: ok_id} = insert!([ref: 1, action: "OK"], tags: ["baz"])
    %Job{id: error_id} = insert!([ref: 2, action: "ERROR"], tags: ["foo"])

    assert_receive {:event, :start, started_time, start_meta}
    assert_receive {:event, :stop, %{duration: stop_duration, queue_time: queue_time}, stop_meta}
    assert_receive {:event, :exception, error_duration, %{kind: :error} = error_meta}

    assert started_time > 0
    assert stop_duration > 0
    assert queue_time > 0
    assert error_duration > 0

    assert %{conf: %Config{name: ^name}, job: %Job{}} = start_meta
    assert %{conf: %Config{name: ^name}, job: %Job{id: ^ok_id}, result: :ok} = stop_meta
    assert %{conf: %Config{name: ^name}, job: %Job{id: ^error_id}} = error_meta

    assert %{job: %Job{unsaved_error: unsaved}} = error_meta
    assert %{kind: :error, reason: %PerformError{}, stacktrace: []} = unsaved

    # Deprecated Meta

    assert %{
             id: ^ok_id,
             args: %{},
             queue: "alpha",
             worker: "Oban.Integration.Worker",
             prefix: "public",
             attempt: 1,
             max_attempts: 20,
             state: :success,
             tags: ["baz"]
           } = stop_meta

    assert %{
             id: ^error_id,
             args: %{},
             queue: "alpha",
             worker: "Oban.Integration.Worker",
             prefix: "public",
             attempt: 1,
             max_attempts: 20,
             kind: :error,
             error: %PerformError{},
             stacktrace: [],
             state: :failure,
             tags: ["foo"]
           } = error_meta
  after
    :telemetry.detach("job-handler")
  end

  test "the default handler logs detailed event information" do
    start_supervised_oban!(queues: [alpha: 3])

    :ok = Telemetry.attach_default_logger(:warn)

    logged =
      capture_log(fn ->
        insert!(ref: 1, action: "OK")

        assert_receive {:ok, 1}

        Process.sleep(50)
      end)

    # Start

    assert logged =~ ~s("source":"oban")
    assert logged =~ ~s("event":"job:start")

    # Stop

    assert logged =~ ~s("source":"oban")
    assert logged =~ ~s("event":"job:stop")
    assert logged =~ ~s("args":)
    assert logged =~ ~s("worker":"Oban.Integration.Worker")
    assert logged =~ ~s("queue":"alpha")
    assert logged =~ ~r|"duration":\d{2,5},|
    assert logged =~ ~r|"queue_time":\d{2,},|
  after
    :telemetry.detach("oban-default-logger")
  end

  test "the default handler logs circuit breaker information" do
    name = start_supervised_oban!(queues: [alpha: 3])

    :ok = Telemetry.attach_default_logger(:warn)

    logged =
      capture_log(fn ->
        assert %{conn: conn} = :sys.get_state(Oban.Registry.whereis(name, Oban.Notifier))
        assert Process.exit(conn, :forced_exit)

        # Give it time to log
        Process.sleep(50)
      end)

    assert logged =~ ~s("event":"circuit:trip")
    assert logged =~ ~s("message":":forced_exit")
    assert logged =~ ~s("name":"Elixir.Oban.Notifier")
  after
    :telemetry.detach("oban-default-logger")
  end

  test "the default handler supports custom telemetry prefixes" do
    name = start_supervised_oban!(telemetry_prefix: [:custom_prefix], queues: [alpha: 3])

    :ok = Telemetry.attach_default_logger(telemetry_prefix: [:custom_prefix], logger_level: :warn)

    Oban.config(name)

    logged =
      capture_log(fn ->
        assert %{conn: conn} = :sys.get_state(Oban.Registry.whereis(name, Oban.Notifier))
        assert Process.exit(conn, :forced_exit)

        # Give it time to log
        Process.sleep(50)
      end)

    assert logged =~ ~s("event":"circuit:trip")
    assert logged =~ ~s("message":":forced_exit")
    assert logged =~ ~s("name":"Elixir.Oban.Notifier")
  after
    :telemetry.detach("oban-default-logger")
  end
end
