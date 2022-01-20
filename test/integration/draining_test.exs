defmodule Oban.Integration.DrainingTest do
  use Oban.Case

  @moduletag :integration

  test "all jobs in a queue can be drained and executed synchronously" do
    name = start_supervised_oban!(queues: false)

    insert!(ref: 1, action: "OK")
    insert!(ref: 2, action: "FAIL")
    insert!(ref: 3, action: "OK")
    insert!(ref: 4, action: "SNOOZE")
    insert!(%{ref: 5, action: "FAIL"}, max_attempts: 1)

    assert %{failure: 2, snoozed: 1, success: 2} == Oban.drain_queue(name, queue: :alpha)

    assert_received {:ok, 3}
    assert_received {:fail, 2}
    assert_received {:ok, 1}
  end

  describe ":with_scheduled" do
    test "scheduled jobs are executed when given the :with_scheduled flag" do
      name = start_supervised_oban!(queues: false)

      insert!(%{ref: 1, action: "OK"}, scheduled_at: seconds_from_now(3600))

      assert %{success: 0, failure: 0} = Oban.drain_queue(name, queue: :alpha)

      assert %{success: 1, failure: 0} =
               Oban.drain_queue(name, queue: :alpha, with_scheduled: true)
    end
  end

  describe ":with_safety" do
    test "job errors bubble up when :with_safety is false" do
      name = start_supervised_oban!(queues: false)

      insert!(ref: 1, action: "FAIL")

      assert_raise RuntimeError, "FAILED", fn ->
        Oban.drain_queue(name, queue: :alpha, with_safety: false)
      end

      assert_received {:fail, 1}
    end

    test "job crashes bubble up when :with_safety is false" do
      name = start_supervised_oban!(queues: false)

      insert!(ref: 1, action: "EXIT")

      assert_raise Oban.CrashError, fn ->
        Oban.drain_queue(name, queue: :alpha, with_safety: false)
      end

      assert_received {:exit, 1}
    end
  end

  describe ":with_recursion" do
    test "jobs inserted during perform are executed when :with_recursion is used" do
      name = start_supervised_oban!(queues: false)

      insert!(ref: 1, recur: 3)

      assert %{success: 3} = Oban.drain_queue(name, queue: :alpha, with_recursion: true)

      assert_received {:ok, 1, 3}
      assert_received {:ok, 2, 3}
      assert_received {:ok, 3, 3}
    end
  end

  describe ":with_limit" do
    test "only the specified number of jobs are executed when :with_limit is used" do
      name = start_supervised_oban!(queues: false)

      insert!(ref: 1, action: "OK")
      insert!(ref: 2, action: "OK")

      assert %{success: 1} = Oban.drain_queue(name, queue: :alpha, with_limit: 1)

      assert_received {:ok, 1}
      refute_received {:ok, 2}
    end
  end
end
