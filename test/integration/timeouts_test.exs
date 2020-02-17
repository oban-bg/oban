defmodule Oban.Integration.TimeoutsTest do
  use Oban.Case

  @moduletag :integration

  @oban_opts repo: Repo, queues: [alpha: 5]

  setup do
    start_supervised!({Oban, @oban_opts})

    :ok
  end

  test "jobs that exceed the worker's timeout are failed" do
    job = insert_job!(%{ref: 1, sleep: 50, timeout: 20})

    assert_receive {:started, 1}
    refute_receive {:ok, 1}

    assert %Job{state: "retryable", errors: [%{"error" => error}]} = Repo.reload(job)
    assert error =~ "Erlang error: :timeout"
  end

  defp insert_job!(args) do
    args
    |> Worker.new(queue: :alpha)
    |> Oban.insert!()
  end
end
