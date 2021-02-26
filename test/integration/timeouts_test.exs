defmodule Oban.Integration.TimeoutsTest do
  use Oban.Case

  @moduletag :integration

  test "jobs that exceed the worker's timeout fail" do
    start_supervised_oban!(queues: [alpha: 5])

    job = insert!(ref: 1, sleep: 100, timeout: 20)

    assert_receive {:started, 1}
    refute_receive {:ok, 1}

    assert %Job{state: "retryable", errors: [%{"error" => error}]} = Repo.reload(job)
    assert error == "** (Oban.TimeoutError) Oban.Integration.Worker timed out after 20ms"
  end
end
