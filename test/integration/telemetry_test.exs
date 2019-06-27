defmodule Oban.Integration.TelemetryTest do
  use Oban.Case

  @moduletag :integration

  @oban_opts repo: Repo, queues: [zeta: 3]

  defmodule Handler do
    def handle([:oban, event], %{duration: duration}, meta, pid) do
      send(pid, {:executed, event, duration, meta})
    end
  end

  test "telemetry events are emitted for executed jobs" do
    events = [[:oban, :success], [:oban, :failure]]

    :telemetry.attach_many("job-handler", events, &Handler.handle/4, self())

    {:ok, _} = start_supervised({Oban, @oban_opts})

    %Job{id: success_id} = insert_job!(%{ref: 1, action: "OK"})
    %Job{id: exception_id} = insert_job!(%{ref: 2, action: "FAIL"})
    %Job{id: error_id} = insert_job!(%{ref: 2, action: "ERROR"})

    assert_receive {:executed, :success, success_duration, success_meta}
    assert_receive {:executed, :failure, exception_duration, %{kind: :exception} = exception_meta}
    assert_receive {:executed, :failure, error_duration, %{kind: :error} = error_meta}

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
  end

  defp insert_job!(args) do
    args
    |> Map.put(:bin_pid, Worker.pid_to_bin())
    |> Worker.new(queue: "zeta")
    |> Repo.insert!()
  end
end
