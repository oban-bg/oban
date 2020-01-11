defmodule Oban.WorkerTest do
  use ExUnit.Case, async: true

  alias Oban.{Job, Worker}

  defmodule BasicWorker do
    use Worker

    @impl Worker
    def perform(_args, _job), do: :ok
  end

  defmodule CustomWorker do
    # Using a module attribute to ensure that module attributes and other non-primitive values can
    # be used when compiling a worker.
    @max_attempts 1

    use Worker,
      queue: "special",
      max_attempts: @max_attempts,
      priority: 1,
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

    test "building a job deep merges unique options" do
      job =
        %{}
        |> CustomWorker.new(unique: [period: 90])
        |> Ecto.Changeset.apply_changes()

      assert job.unique.fields == [:queue, :worker]
      assert job.unique.period == 90
      assert job.unique.states == [:scheduled]
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

    test "validating that the first argument is a map with string keys" do
      assert_raise ArgumentError, fn ->
        defmodule AtomKeys do
          use Oban.Worker

          def perform(%{a: 1}, _), do: :ok
        end
      end

      assert_raise ArgumentError, fn ->
        defmodule MixedKeys do
          use Oban.Worker

          def perform(%{"a" => 1}, _), do: :ok
          def perform(%{b: 2}, _), do: :ok
        end
      end

      assert_raise ArgumentError, fn ->
        defmodule WrongType do
          use Oban.Worker

          def perform([a: 1, b: 2], _), do: :ok
        end
      end

      assert_raise ArgumentError, fn ->
        defmodule NestedMaps do
          use Oban.Worker

          def perform(%{"a" => %{b: 2}}, _), do: :ok
        end
      end
    end
  end

  test "validating __using__ macro options" do
    assert_raise ArgumentError, fn ->
      defmodule BrokenModuleA do
        use Oban.Worker, state: "youcantsetthis"

        def perform(_, _), do: :ok
      end
    end

    assert_raise ArgumentError, fn ->
      defmodule BrokenModuleB do
        use Oban.Worker, queue: 1234

        def perform(_, _), do: :ok
      end
    end

    assert_raise ArgumentError, fn ->
      defmodule BrokenModuleC do
        use Oban.Worker, max_attempts: 0

        def perform(_, _), do: :ok
      end
    end

    assert_raise ArgumentError, fn ->
      defmodule BrokenModuleD do
        use Oban.Worker, priority: 11

        def perform(_, _), do: :ok
      end
    end

    assert_raise ArgumentError, fn ->
      defmodule BrokenModuleE do
        use Oban.Worker, unique: 0

        def perform(_, _), do: :ok
      end
    end

    assert_raise ArgumentError, fn ->
      defmodule BrokenModuleF do
        use Oban.Worker, unique: [unknown: []]

        def perform(_, _), do: :ok
      end
    end

    assert_raise ArgumentError, fn ->
      defmodule BrokenModuleG do
        use Oban.Worker, unique: [fields: [:unknown]]

        def perform(_, _), do: :ok
      end
    end

    assert_raise ArgumentError, fn ->
      defmodule BrokenModuleH do
        use Oban.Worker, unique: [period: 0]

        def perform(_, _), do: :ok
      end
    end

    assert_raise ArgumentError, fn ->
      defmodule BrokenModuleI do
        use Oban.Worker, unique: [states: [:unknown]]

        def perform(_, _), do: :ok
      end
    end
  end
end
