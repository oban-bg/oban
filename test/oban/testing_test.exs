defmodule Oban.TestingTest do
  use Oban.Case, async: true

  use Oban.Testing, repo: Oban.Test.Repo

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
  end

  describe "refute_enqueued/1" do
    test "refuting jobs with specific properties have been enqueued" do
      insert_job!(%{id: 1}, worker: Ping, queue: :alpha)
      insert_job!(%{id: 2}, worker: Pong, queue: :gamma)
      insert_job!(%{message: "hello"}, worker: Pong, queue: :gamma)

      refute_enqueued worker: Pongo
      refute_enqueued worker: Ping, args: %{id: 2}
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
