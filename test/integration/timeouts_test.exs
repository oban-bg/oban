defmodule Oban.Integration.TimeoutsTest do
  use Oban.Case

  @moduletag :integration

  test "jobs that exceed the worker's timeout are failed" do
    start_supervised_oban!(queues: [alpha: 5])

    job = insert!(ref: 1, sleep: 50, timeout: 20)

    assert_receive {:started, 1}
    refute_receive {:ok, 1}

    assert %Job{state: "retryable", errors: [%{"error" => error}]} = Repo.reload(job)
    assert error =~ "Erlang error: :timeout"
  end
end
