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

    %Job{id: succ_id} = insert_job!(%{ref: 1, action: "OK"})
    %Job{id: fail_id} = insert_job!(%{ref: 2, action: "FAIL"})

    assert_receive {:executed, :success, succ_duration, succ_meta}
    assert_receive {:executed, :failure, fail_duration, fail_meta}

    assert succ_duration > 0
    assert fail_duration > 0

    assert %{
             id: ^succ_id,
             args: %{},
             queue: "zeta",
             worker: "Oban.Integration.Worker",
             attempt: 1,
             max_attempts: 20
           } = succ_meta

    assert %{
             id: ^fail_id,
             args: %{},
             queue: "zeta",
             worker: "Oban.Integration.Worker",
             attempt: 1,
             max_attempts: 20
           } = fail_meta

    :ok = stop_supervised(Oban)
  end

  defp insert_job!(args) do
    args
    |> Map.put(:bin_pid, Worker.pid_to_bin())
    |> Worker.new(queue: "zeta")
    |> Repo.insert!()
  end
end
