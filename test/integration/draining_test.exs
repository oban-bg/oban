defmodule Oban.Integration.DrainingTest do
  use Oban.Case

  @moduletag :integration

  @oban_opts repo: Repo, queues: false

  setup do
    start_supervised!({Oban, @oban_opts})

    :ok
  end

  test "all jobs in a queue can be drained and executed synchronously" do
    insert_job!(ref: 1, action: "OK")
    insert_job!(ref: 2, action: "FAIL")
    insert_job!(ref: 3, action: "OK")

    assert %{success: 2, failure: 1} = Oban.drain_queue(:draining)

    assert_received {:ok, 3}
    assert_received {:fail, 2}
    assert_received {:ok, 1}
  end

  test "scheduled jobs are executed when given the :with_scheduled flag" do
    insert_job!(%{ref: 1, action: "OK"}, scheduled_at: seconds_from_now(3600))

    assert %{success: 0, failure: 0} = Oban.drain_queue(:draining)
    assert %{success: 1, failure: 0} = Oban.drain_queue(:draining, with_scheduled: true)
  end

  test "job errors bubble up when :with_safety is false" do
    insert_job!(ref: 1, action: "FAIL")

    assert_raise RuntimeError, "FAILED", fn ->
      Oban.drain_queue(:draining, with_safety: false)
    end

    assert_received {:fail, 1}
  end

  test "job crashes bubble up when :with_safety is false" do
    insert_job!(ref: 1, action: "EXIT")

    assert catch_exit(Oban.drain_queue(:draining, with_safety: false))

    assert_received {:exit, 1}
  end

  defp insert_job!(args, opts \\ []) do
    opts = Keyword.put_new(opts, :queue, :draining)

    args
    |> Worker.new(opts)
    |> Oban.insert!()
  end
end
