defmodule Oban.Integration.ResiliencyTest do
  use Oban.Case

  @moduletag :integration

  @oban_opts repo: Repo, queues: [alpha: 1], poll_interval: 10

  defmodule Handler do
    def handle([:oban, :trip_circuit], %{}, meta, pid) do
      send(pid, {:tripped, meta})
    end
  end

  setup do
    :telemetry.attach("circuit-handler", [:oban, :trip_circuit], &Handler.handle/4, self())

    on_exit(fn -> :telemetry.detach("circuit-handler") end)
  end

  test "producer connection errors are logged in resilient mode" do
    mangle_jobs_table!()

    start_supervised!({Oban, @oban_opts})

    assert_receive {:tripped, %{message: message, name: name}}

    assert message =~ ~s|ERROR 42P01 (undefined_table)|
    assert name == Oban.Queue.Alpha.Producer

    :ok = stop_supervised(Oban)
  after
    reform_jobs_table!()
  end

  test "notification connection errors are logged in resilient mode" do
    start_supervised!({Oban, @oban_opts})

    assert %{conn: conn} = :sys.get_state(Oban.Notifier)
    assert Process.exit(conn, :forced_exit)

    # This verifies that producer's are isolated from the notifier
    insert_job!(ref: 1, action: "OK")

    assert_receive {:ok, 1}

    assert_receive {:tripped, %{message: ":forced_exit"}}

    :ok = stop_supervised(Oban)
  end

  test "recording job completion is retried after errors" do
    start_supervised!({Oban, @oban_opts})

    job = insert_job!(ref: 1, sleep: 10)

    assert_receive {:started, 1}

    mangle_jobs_table!()

    assert_receive {:ok, 1}

    reform_jobs_table!()

    with_backoff([sleep: 50, total: 10], fn ->
      assert %{state: "completed"} = Repo.reload(job)
    end)

    :ok = stop_supervised(Oban)
  end

  defp insert_job!(args) do
    args
    |> Worker.new(queue: :alpha)
    |> Oban.insert!()
  end

  defp mangle_jobs_table! do
    Repo.query!("ALTER TABLE oban_jobs RENAME TO oban_missing")
  end

  defp reform_jobs_table! do
    Repo.query!("ALTER TABLE oban_missing RENAME TO oban_jobs")
  end
end
