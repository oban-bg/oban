defmodule Oban.Integration.ResiliencyTest do
  use Oban.Case

  import ExUnit.CaptureLog

  @moduletag :integration

  @oban_opts repo: Repo, queues: [alpha: 1, gamma: 1], poll_interval: 10

  test "producer connection errors are logged in resilient mode" do
    Repo.query!("ALTER TABLE oban_jobs RENAME TO oban_missing")

    logged =
      capture_log([level: :error], fn ->
        start_supervised!({Oban, @oban_opts})
        Process.sleep(50)
      end)

    assert logged =~ ~s|"source":"oban"|
    assert logged =~ ~s|"message":"Circuit temporarily tripped"|
    assert logged =~ ~s|"error":"ERROR 42P01 (undefined_table)|

    :ok = stop_supervised(Oban)
  after
    Repo.query!("ALTER TABLE oban_missing RENAME TO oban_jobs")
  end

  test "notification connection errors are logged in resilient mode" do
    start_supervised!({Oban, @oban_opts})

    logged =
      capture_log([level: :error], fn ->
        assert %{conn: conn} = :sys.get_state(Oban.Notifier)
        assert Process.exit(conn, :forced_exit)

        # This verifies that producer's are isolated from the notifier
        insert_job!(ref: 1, action: "OK")

        assert_receive {:ok, 1}
      end)

    assert logged =~ ~s|"source":"oban"|
    assert logged =~ ~s|"message":"Circuit temporarily tripped"|
    assert logged =~ ~s|"error":":forced_exit"|

    :ok = stop_supervised(Oban)
  end

  defp insert_job!(args) do
    args
    |> Worker.new(queue: :alpha)
    |> Oban.insert!()
  end
end
