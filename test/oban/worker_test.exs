defmodule Oban.WorkerTest do
  use ExUnit.Case, async: true

  alias Oban.{Job, Worker}

  defmodule BasicWorker do
    use Worker
  end

  defmodule CustomWorker do
    use Worker, queue: "special", max_attempts: 5, unique: [period: 60]

    @impl Worker
    def backoff(attempt), do: attempt * attempt

    @impl Worker
    def perform(%{attempt: attempt}) when attempt > 1, do: attempt
    def perform(%{a: a, b: b}), do: a + b
  end

  describe "new/2" do
    test "building a job through the worker presets options" do
      job =
        %{a: 1, b: 2}
        |> CustomWorker.new()
        |> Ecto.Changeset.apply_changes()

      assert job.args == %{a: 1, b: 2}
      assert job.queue == "special"
      assert job.max_attempts == 5
      assert job.worker == "Oban.WorkerTest.CustomWorker"
      assert job.unique.period == 60
    end
  end

  describe "backoff/1" do
    test "the default backoff uses an exponential algorithm with a fixed padding" do
      assert BasicWorker.backoff(1) == 17
      assert BasicWorker.backoff(2) == 19
      assert BasicWorker.backoff(4) == 31
      assert BasicWorker.backoff(5) == 47
    end

    test "the backoff can be overridden" do
      assert CustomWorker.backoff(1) == 1
      assert CustomWorker.backoff(2) == 4
      assert CustomWorker.backoff(3) == 9
    end
  end

  describe "perform/1" do
    test "a default implementation is provided" do
      assert :ok = BasicWorker.perform(%{})
      assert :ok = BasicWorker.perform(%Job{args: %{}})
    end

    test "the implementation may be overridden" do
      assert 5 == CustomWorker.perform(%{a: 2, b: 3})
    end

    test "arguments from the complete job struct are extracted" do
      assert 5 == CustomWorker.perform(%Job{args: %{a: 2, b: 3}})
      assert 4 == CustomWorker.perform(%Job{attempt: 4, args: %{a: 2, b: 3}})
    end
  end
end
