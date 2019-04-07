defmodule Oban.Integration.TelemetryTest do
  use Oban.Case

  @moduletag :integration

  @oban_opts repo: Repo, queues: [zeta: 3]

  defmodule Handler do
    def handle([:oban, :job, :executed], %{timing: timing}, meta, pid) do
      send(pid, {:executed, meta[:event], timing})
    end
  end

  test "telemetry events are emitted for executed jobs" do
    :telemetry.attach("job-handler", [:oban, :job, :executed], &Handler.handle/4, self())

    {:ok, _} = start_supervised({Oban, @oban_opts})

    insert_job!(%{ref: 1, action: "OK"})
    insert_job!(%{ref: 2, action: "FAIL"})

    assert_receive {:executed, :success, success_timing}
    assert_receive {:executed, :failure, failure_timing}

    assert success_timing > 0
    assert failure_timing > 0

    :ok = stop_supervised(Oban)
  end

  defp insert_job!(args) do
    args
    |> Map.put(:bin_pid, Worker.pid_to_bin())
    |> Worker.new(queue: "zeta")
    |> Repo.insert!()
  end
end
