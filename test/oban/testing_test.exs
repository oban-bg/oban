defmodule Oban.TestingTest do
  use Oban.Case

  use Oban.Testing, repo: Oban.Test.Repo

  @moduletag :integration

  describe "all_enqueued/1" do
    test "retrieving a filtered list of enqueued jobs" do
      insert!(%{id: 1, ref: "a"}, worker: Ping, queue: :alpha)
      insert!(%{id: 2, ref: "b"}, worker: Ping, queue: :alpha)
      insert!(%{id: 3, ref: "c"}, worker: Pong, queue: :gamma)

      assert [%{args: %{"id" => 2}} | _] = all_enqueued(worker: Ping)
      assert [%Oban.Job{}] = all_enqueued(worker: Pong, queue: :gamma)
    end
  end

  describe "assert_enqueued/1" do
    test "checking for jobs with matching properties" do
      insert!(%{id: 1}, worker: Ping, queue: :alpha)
      insert!(%{id: 2}, worker: Pong, queue: :gamma)
      insert!(%{message: "hello"}, worker: Pong, queue: :gamma)

      assert_enqueued worker: Ping
      assert_enqueued worker: Ping, queue: :alpha
      assert_enqueued worker: Ping, queue: :alpha, args: %{id: 1}
      assert_enqueued worker: Pong
      assert_enqueued worker: "Pong", queue: "gamma"
      assert_enqueued worker: "Pong", queue: "gamma", args: %{message: "hello"}
      assert_enqueued args: %{id: 1}
      assert_enqueued args: %{message: "hello"}
    end

    test "checking for jobs with matching timestamps with delta" do
      insert!(%{}, worker: Ping, scheduled_at: seconds_from_now(60))

      assert_enqueued worker: Ping, scheduled_at: seconds_from_now(60)
    end

    test "checking for jobs allows to configure timetamp delta" do
      insert!(%{}, worker: Ping, scheduled_at: seconds_from_now(60))

      assert_enqueued worker: Ping, scheduled_at: {seconds_from_now(69), delta: 10}
    end

    test "asserting that jobs are now or will eventually be enqueued" do
      insert!(%{id: 1}, worker: Ping, queue: :alpha)

      Task.async(fn ->
        Process.sleep(50)

        insert!(%{id: 2}, worker: Pong, queue: :alpha)
      end)

      assert_enqueued [worker: Pong, args: %{id: 2}], 100
      assert_enqueued [worker: Ping, args: %{id: 1}], 100
    end

    test "printing a helpful error message" do
      insert!(%{dest: "some_node"}, worker: Ping)

      try do
        assert_enqueued worker: Ping, args: %{dest: "other_node"}
      rescue
        error in [ExUnit.AssertionError] ->
          expected = """
          Expected a job matching:

          %{args: %{dest: "other_node"}, worker: Ping}

          to be enqueued. Instead found:

          [%{args: %{"dest" => "some_node"}, worker: "Ping"}]
          """

          assert error.message == expected
      end
    end
  end

  describe "refute_enqueued/1" do
    test "refuting jobs with specific properties have been enqueued" do
      insert!(%{id: 1}, worker: Ping, queue: :alpha)
      insert!(%{id: 2}, worker: Pong, queue: :gamma)
      insert!(%{id: 3}, worker: Pong, queue: :gamma, state: "completed")
      insert!(%{id: 4}, worker: Pong, queue: :gamma, state: "discarded")
      insert!(%{message: "hello"}, worker: Pong, queue: :gamma)

      refute_enqueued worker: Pongo
      refute_enqueued worker: Ping, args: %{id: 2}
      refute_enqueued worker: Pong, args: %{id: 3}
      refute_enqueued worker: Pong, args: %{id: 4}
      refute_enqueued worker: Ping, queue: :gamma
      refute_enqueued worker: Pong, queue: :gamma, args: %{message: "helo"}
    end

    test "refuting that jobs are now or will eventually be enqueued" do
      Task.async(fn ->
        Process.sleep(50)

        insert!(%{id: 1}, worker: Ping, queue: :alpha)
      end)

      refute_enqueued [worker: Ping, args: %{id: 1}], 20
    end
  end
end
