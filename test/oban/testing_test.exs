defmodule Oban.TestingTest do
  use Oban.Case

  use Oban.Testing, repo: Oban.Test.Repo

  @moduletag :integration

  describe "all_enqueued/1" do
    test "retrieving a filtered list of enqueued jobs" do
      insert_job!(%{id: 1, ref: "a"}, worker: Ping, queue: :alpha)
      insert_job!(%{id: 2, ref: "b"}, worker: Ping, queue: :alpha)
      insert_job!(%{id: 3, ref: "c"}, worker: Pong, queue: :gamma)

      assert [%{args: %{"id" => 2}} | _] = all_enqueued(worker: Ping)
      assert [%Oban.Job{}] = all_enqueued(worker: Pong, queue: :gamma)
    end
  end

  describe "assert_enqueued/1" do
    test "checking for jobs with matching properties" do
      insert_job!(%{id: 1}, worker: Ping, queue: :alpha)
      insert_job!(%{id: 2}, worker: Pong, queue: :gamma)
      insert_job!(%{message: "hello"}, worker: Pong, queue: :gamma)

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
      insert_job!(%{}, worker: Ping, scheduled_at: seconds_from_now(60))

      assert_enqueued worker: Ping, scheduled_at: seconds_from_now(60)
    end

    test "checking for jobs allows to configure timetamp delta" do
      insert_job!(%{}, worker: Ping, scheduled_at: seconds_from_now(60))

      assert_enqueued worker: Ping, scheduled_at: {seconds_from_now(69), delta: 10}
    end
  end

  describe "refute_enqueued/1" do
    test "refuting jobs with specific properties have been enqueued" do
      insert_job!(%{id: 1}, worker: Ping, queue: :alpha)
      insert_job!(%{id: 2}, worker: Pong, queue: :gamma)
      insert_job!(%{id: 3}, worker: Pong, queue: :gamma, state: "completed")
      insert_job!(%{id: 4}, worker: Pong, queue: :gamma, state: "discarded")
      insert_job!(%{message: "hello"}, worker: Pong, queue: :gamma)

      refute_enqueued worker: Pongo
      refute_enqueued worker: Ping, args: %{id: 2}
      refute_enqueued worker: Pong, args: %{id: 3}
      refute_enqueued worker: Pong, args: %{id: 4}
      refute_enqueued worker: Ping, queue: :gamma
      refute_enqueued worker: Pong, queue: :gamma, args: %{message: "helo"}
    end
  end

  defp insert_job!(args, opts) do
    args
    |> Job.new(opts)
    |> Repo.insert!()
  end
end
