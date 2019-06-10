defmodule Oban.Integration.ResiliencyTest do
  use Oban.Case

  import ExUnit.CaptureLog

  @moduletag :integration

  @oban_opts repo: Repo, queues: [alpha: 1, gamma: 1]

  test "producer connection errors are logged in resilient mode" do
    Repo.query!("ALTER TABLE oban_jobs RENAME TO oban_missing")

    logged =
      capture_log([level: :error], fn ->
        start_supervised!({Oban, @oban_opts})
        Process.sleep(50)
      end)

    assert logged =~ ~s|"source":"oban"|
    assert logged =~ ~s|"message":"Circuit temporarily tripped by Postgrex.Error"|
    assert logged =~ ~s|"error":"ERROR 42P01 (undefined_table)|

    :ok = stop_supervised(Oban)
  after
    Repo.query!("ALTER TABLE oban_missing RENAME TO oban_jobs")
  end
end
