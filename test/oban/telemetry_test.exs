defmodule Oban.TelemetryTest do
  use Oban.Case

  import ExUnit.CaptureLog

  alias Oban.{Config, PerformError, Telemetry, TelemetryHandler}

  def handle_query(_event, _measure, meta, pid) do
    send(pid, {:query, meta})
  end

  test "repo operations include the oban config" do
    :telemetry.attach(
      "repo-test",
      [:oban, :test, :repo, :query],
      &__MODULE__.handle_query/4,
      self()
    )

    name = start_supervised_oban!(queues: [alpha: 2])
    conf = Oban.config(name)

    Oban.Repo.all(conf, Oban.Job)

    assert_received {:query, %{options: [oban_conf: ^conf]}}
  after
    :telemetry.detach("repo-test")
  end

  test "telemetry event is emitted for supervisor initialization" do
    TelemetryHandler.attach_events()

    name = start_supervised_oban!(queues: [alpha: 2])
    pid = Oban.Registry.whereis(name)
    conf = Oban.config(name)

    assert_receive {:event, [:oban, :supervisor, :init], %{system_time: _},
                    %{conf: ^conf, pid: ^pid}}
  end

  test "telemetry events are emitted for executed jobs" do
    TelemetryHandler.attach_events(span_type: [:job])

    name = start_supervised_oban!(stage_interval: 10, queues: [alpha: 2])

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
    assert %{conf: %Config{name: ^name}, job: %Job{id: ^error_id}, result: _} = error_meta

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
  end

  test "the default handler logs detailed event information" do
    :ok = Telemetry.attach_default_logger(:warning)

    start_supervised_oban!(
      notifier: Oban.Notifiers.Postgres,
      queues: [alpha: 3],
      stage_interval: 10
    )

    logged =
      capture_log(fn ->
        insert!(ref: 1, action: "OK")
        insert!(ref: 2, action: "ERROR")

        assert_receive {:ok, 1}
        assert_receive {:error, 2}

        Process.sleep(50)
      end)

    Logger.flush()

    # Start

    assert logged =~ ~s("source":"oban")
    assert logged =~ ~s("event":"job:start")

    # Stop

    assert logged =~ ~s("event":"job:stop")
    assert logged =~ ~s("args":{)
    assert logged =~ ~s("attempt":1)
    assert logged =~ ~s("id":)
    assert logged =~ ~s("max_attempts":20)
    assert logged =~ ~s("meta":{)
    assert logged =~ ~s("queue":"alpha")
    assert logged =~ ~s("state":"success")
    assert logged =~ ~s("tags":[])
    assert logged =~ ~s("worker":"Oban.Integration.Worker")
    assert logged =~ ~r|"duration":\d{1,}|
    assert logged =~ ~r|"queue_time":\d{1,}|

    # Exception
    assert logged =~ ~s("event":"job:exception")
    assert logged =~ ~s("state":"failure")
    assert logged =~ ~s|"error":"** (Oban.PerformError)|
  after
    Telemetry.detach_default_logger()
  end

  test "the default handler logs stager switch events" do
    :ok = Telemetry.attach_default_logger(:warning)

    logged =
      capture_log(fn ->
        :telemetry.execute([:oban, :stager, :switch], %{}, %{mode: :local})
      end)

    assert logged =~ ~s("source":"oban")
    assert logged =~ ~s("event":"stager:switch")
    assert logged =~ ~s("message":"job staging switched to local mode)
  after
    Telemetry.detach_default_logger()
  end

  test "the default handler logs notifier switch events" do
    :ok = Telemetry.attach_default_logger(:warning)

    logged =
      capture_log(fn ->
        :telemetry.execute([:oban, :notifier, :switch], %{}, %{status: :isolated})
      end)

    assert logged =~ ~s("source":"oban")
    assert logged =~ ~s("event":"notifier:switch")
    assert logged =~ ~s("message":"notifier can't receive messages)
  after
    Telemetry.detach_default_logger()
  end

  test "detaching the logger prevents logging" do
    :ok = Telemetry.attach_default_logger(:warning)
    :ok = Telemetry.detach_default_logger()

    assert capture_log(fn ->
             :telemetry.execute([:oban, :notifier, :switch], %{}, %{status: :isolated})
           end) == ""
  end

  test "disabling encoding on the default logger" do
    start_supervised_oban!(stage_interval: 10, queues: [alpha: 3])

    :ok = Telemetry.attach_default_logger(encode: false, level: :warning)

    logged =
      capture_log(fn ->
        insert!(ref: 1, action: "OK")

        assert_receive {:ok, 1}

        Logger.flush()
      end)

    assert logged =~ ~s(source: "oban")
    assert logged =~ ~s(event: "job:start")
  after
    Telemetry.detach_default_logger()
  end
end
