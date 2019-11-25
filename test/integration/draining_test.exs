defmodule Oban.Integration.DrainingTest do
  use Oban.Case

  @moduletag :integration

  @oban_opts repo: Repo, queues: false

  test "all jobs in a queue can be drained and executed synchronously" do
    start_supervised!({Oban, @oban_opts})

    insert_job!(ref: 1, action: "OK")
    insert_job!(ref: 2, action: "FAIL")
    insert_job!(ref: 3, action: "OK")

    assert %{success: 2, failure: 1} = Oban.drain_queue(:draining)

    assert_received {:ok, 3}
    assert_received {:fail, 2}
    assert_received {:ok, 1}

    stop_supervised(Oban)
  end

  test "scheduled jobs are not executed by default" do
    start_supervised!({Oban, @oban_opts})

    insert_scheduled_job!()

    assert %{success: 0, failure: 0} = Oban.drain_queue(:draining)

    stop_supervised(Oban)
  end

  test "scheduled jobs are executed when given the :with_scheduled flag" do
    start_supervised!({Oban, @oban_opts})

    insert_scheduled_job!()

    assert %{success: 1, failure: 0} = Oban.drain_queue(:draining, with_scheduled: true)

    stop_supervised(Oban)
  end

  test "drain_queue/2 allows to pass in the config name as first argument" do
    start_supervised!({Oban, @oban_opts})

    insert_job!()

    assert %{success: 1, failure: 0} = Oban.drain_queue(Oban, :draining)

    stop_supervised(Oban)
  end

  defp insert_job! do
    insert_job!(ref: 1, action: "OK")
  end

  defp insert_job!(args) do
    args
    |> Worker.new(queue: :draining)
    |> Oban.insert!()
  end

  defp insert_scheduled_job! do
    %{ref: 1, action: "OK"}
    |> Worker.new(queue: :draining, scheduled_at: seconds_from_now(3600))
    |> Oban.insert!()
  end
end
