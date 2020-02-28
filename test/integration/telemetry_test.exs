defmodule Oban.Integration.TelemetryTest do
  use Oban.Case

  import ExUnit.CaptureLog

  alias Oban.Telemetry

  @moduletag :integration

  @oban_opts repo: Repo, queues: [zeta: 3]

  defmodule Handler do
    def handle([:oban, :started], %{start_time: start_time}, meta, pid) do
      send(pid, {:executed, :started, start_time, meta})
    end

    def handle([:oban, event], %{duration: duration}, meta, pid) do
      send(pid, {:executed, event, duration, meta})
    end
  end

  test "telemetry events are emitted for executed jobs" do
    events = [[:oban, :started], [:oban, :success], [:oban, :failure]]

    :telemetry.attach_many("job-handler", events, &Handler.handle/4, self())

    start_supervised!({Oban, @oban_opts})

    %Job{id: success_id} = insert_job!(%{ref: 1, action: "OK"})
    %Job{id: exception_id} = insert_job!(%{ref: 2, action: "FAIL"})
    %Job{id: error_id} = insert_job!(%{ref: 2, action: "ERROR"})

    assert_receive {:executed, :started, started_time, success_meta}
    assert_receive {:executed, :success, success_duration, success_meta}
    assert_receive {:executed, :failure, exception_duration, %{kind: :exception} = exception_meta}
    assert_receive {:executed, :failure, error_duration, %{kind: :error} = error_meta}

    assert started_time > 0
    assert success_duration > 0
    assert exception_duration > 0
    assert error_duration > 0

    assert %{
             id: ^success_id,
             args: %{},
             queue: "zeta",
             worker: "Oban.Integration.Worker",
             attempt: 1,
             max_attempts: 20
           } = success_meta

    assert %{
             id: ^exception_id,
             args: %{},
             queue: "zeta",
             worker: "Oban.Integration.Worker",
             attempt: 1,
             max_attempts: 20,
             kind: :exception,
             error: _,
             stack: [_ | _]
           } = exception_meta

    assert %{
             id: ^error_id,
             args: %{},
             queue: "zeta",
             worker: "Oban.Integration.Worker",
             attempt: 1,
             max_attempts: 20,
             kind: :error,
             error: "ERROR",
             stack: [_ | _]
           } = error_meta

    :ok = stop_supervised(Oban)
  after
    :telemetry.detach("job-handler")
  end

  test "the default handler logs detailed event information" do
    start_supervised!({Oban, @oban_opts})

    :ok = Telemetry.attach_default_logger(:warn)

    logged =
      capture_log(fn ->
        insert_job!(%{ref: 1, action: "OK"})

        assert_receive {:ok, 1}

        Process.sleep(10)
      end)

    # Started

    assert logged =~ ~s("source":"oban")
    assert logged =~ ~s("event":"started")
    assert logged =~ ~s("start_time":)

    # Success

    assert logged =~ ~s("source":"oban")
    assert logged =~ ~s("event":"success")
    assert logged =~ ~s("args":)
    assert logged =~ ~s("worker":"Oban.Integration.Worker")
    assert logged =~ ~s("queue":"zeta")
    assert logged =~ ~s("duration":)
  after
    :telemetry.detach("oban-default-logger")
  end

  test "the default handler logs circuit breaker information" do
    start_supervised!({Oban, @oban_opts})

    :ok = Telemetry.attach_default_logger(:warn)

    logged =
      capture_log(fn ->
        assert %{conn: conn} = :sys.get_state(Oban.Notifier)
        assert Process.exit(conn, :forced_exit)

        # Give it time to log
        Process.sleep(50)
      end)

    assert logged =~ ~s("event":"trip_circuit")
    assert logged =~ ~s("message":":forced_exit")
    assert logged =~ ~s("name":"Elixir.Oban.Notifier")
  after
    :telemetry.detach("oban-default-logger")
  end

  defp insert_job!(args) do
    args
    |> Worker.new(queue: "zeta")
    |> Repo.insert!()
  end
end
