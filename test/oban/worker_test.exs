defmodule Oban.WorkerTest do
  use ExUnit.Case, async: true

  alias Oban.{Job, Worker}

  defmodule BasicWorker do
    use Worker

    @impl Worker
    def perform(_args, _job), do: :ok
  end

  defmodule CustomWorker do
    use Worker,
      queue: "special",
      max_attempts: 1,
      unique: [fields: [:queue, :worker], period: 60, states: [:scheduled]]

    @impl Worker
    def backoff(attempt), do: attempt * attempt

    @impl Worker
    def perform(_args, %{attempt: attempt}) when attempt > 1, do: attempt
    def perform(%{"a" => a, "b" => b}, _job), do: a + b
  end

  describe "new/2" do
    test "building a job through the worker presets options" do
      job =
        %{a: 1, b: 2}
        |> CustomWorker.new()
        |> Ecto.Changeset.apply_changes()

      assert job.args == %{a: 1, b: 2}
      assert job.queue == "special"
      assert job.max_attempts == 1
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

  describe "perform/2" do
    test "arguments from the complete job struct are extracted" do
      args = %{"a" => 2, "b" => 3}

      assert 5 == CustomWorker.perform(args, %Job{args: args})
      assert 4 == CustomWorker.perform(args, %Job{attempt: 4, args: args})
    end
  end

  describe "validating __using__ macro options" do
    assert_raise ArgumentError, fn ->
      defmodule(BrokenModule, do: use(Oban.Worker, state: "youcantsetthis"))
    end

    assert_raise ArgumentError, fn ->
      defmodule(BrokenModule, do: use(Oban.Worker, queue: 1234))
    end

    assert_raise ArgumentError, fn ->
      defmodule(BrokenModule, do: use(Oban.Worker, max_attempts: 0))
    end

    assert_raise ArgumentError, fn ->
      defmodule(BrokenModule, do: use(Oban.Worker, unique: 0))
    end

    assert_raise ArgumentError, fn ->
      defmodule(BrokenModule, do: use(Oban.Worker, unique: [unknown: []]))
    end

    assert_raise ArgumentError, fn ->
      defmodule(BrokenModule, do: use(Oban.Worker, unique: [fields: [:unknown]]))
    end

    assert_raise ArgumentError, fn ->
      defmodule(BrokenModule, do: use(Oban.Worker, unique: [period: 0]))
    end

    assert_raise ArgumentError, fn ->
      defmodule(BrokenModule, do: use(Oban.Worker, unique: [states: [:unknown]]))
    end
  end
end
