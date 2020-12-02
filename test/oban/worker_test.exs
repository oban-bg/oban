defmodule Oban.WorkerTest do
  use ExUnit.Case, async: false

  doctest Oban.Worker

  use ExUnitProperties

  alias Oban.{Job, Worker}

  defmodule BasicWorker do
    use Worker

    @impl Worker
    def perform(_job), do: :ok
  end

  defmodule CustomWorker do
    # Using a module attribute to ensure that module attributes and other non-primitive values can
    # be used when compiling a worker.
    # credo:disable-for-lines:3 Credo.Check.Readability.StrictModuleLayout
    @max_attempts 1

    use Worker,
      queue: "special",
      max_attempts: @max_attempts,
      priority: 1,
      tags: ["scheduled", "special"],
      unique: [fields: [:queue, :worker], period: 60, states: [:scheduled]]

    @impl Worker
    def perform(%{attempt: attempt}) when attempt > 1, do: attempt
    def perform(%{args: %{"a" => a, "b" => b}}), do: a + b
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
    property "the backoff increases with subsequent attempts" do
      check all attempt <- integer(1..19) do
        first = BasicWorker.backoff(%Job{attempt: attempt, max_attempts: 20})
        second = BasicWorker.backoff(%Job{attempt: attempt + 2, max_attempts: 20})

        assert first < second
      end
    end

    property "the default algorithm never exceeds an upper bound" do
      check all attempt <- integer(1..999),
                max_diff <- integer(0..999) do
        job = %Job{attempt: attempt, max_attempts: attempt + max_diff}
        backoff = BasicWorker.backoff(job)
        backoff_for_twenty_attempts = 2_097_167

        assert backoff <= backoff_for_twenty_attempts
      end
    end
  end

  describe "timeout/1" do
    test "the default timeout is infinity" do
      assert BasicWorker.timeout(%Job{}) == :infinity
    end
  end

  describe "perform/1" do
    test "arguments from the complete job struct are extracted" do
      args = %{"a" => 2, "b" => 3}

      assert 5 == CustomWorker.perform(%Job{args: args})
      assert 4 == CustomWorker.perform(%Job{attempt: 4, args: args})
    end
  end

  describe "from_string/1" do
    test "finds workers that are not loaded" do
      :code.delete(Oban.Integration.Worker)

      assert {:ok, Oban.Integration.Worker} = Worker.from_string("Oban.Integration.Worker")
    end
  end

  test "validating __using__ macro options" do
    assert_raise ArgumentError, ~r/unknown option/, fn ->
      defmodule UnknownOption do
        use Oban.Worker, state: "youcantsetthis"

        def perform(_), do: :ok
      end
    end
  end

  test "validating the queue provided to __using__" do
    assert_raise ArgumentError, ~r/expected :queue to be/, fn ->
      defmodule InvalidQueue do
        use Oban.Worker, queue: 1234

        def perform(_), do: :ok
      end
    end
  end

  test "validating the max attempts provided to __using__" do
    assert_raise ArgumentError, ~r/expected :max_attempts to be/, fn ->
      defmodule InvalidMaxAttempts do
        use Oban.Worker, max_attempts: 0

        def perform(_), do: :ok
      end
    end
  end

  test "validating the priority provided to __using__" do
    assert_raise ArgumentError, ~r/expected :priority to be/, fn ->
      defmodule InvalidPriority do
        use Oban.Worker, priority: 11

        def perform(_), do: :ok
      end
    end
  end

  test "validating the tags provided to __using__" do
    assert_raise ArgumentError, ~r/expected :tags to be a list/, fn ->
      defmodule InvalidTagsType do
        use Oban.Worker, tags: nil

        def perform(_), do: :ok
      end
    end

    assert_raise ArgumentError, ~r/expected :tags to be a list/, fn ->
      defmodule InvalidTagsValue do
        use Oban.Worker, tags: ["alpha", :beta]

        def perform(_), do: :ok
      end
    end
  end

  test "validating the unique options provided to __using__" do
    assert_raise ArgumentError, ~r/unexpected unique options/, fn ->
      defmodule InvalidUniqueType do
        use Oban.Worker, unique: 0

        def perform(_), do: :ok
      end
    end

    assert_raise ArgumentError, ~r/unexpected unique options/, fn ->
      defmodule InvalidUniqueOption do
        use Oban.Worker, unique: [unknown: []]

        def perform(_), do: :ok
      end
    end

    assert_raise ArgumentError, ~r/unexpected unique options/, fn ->
      defmodule InvalidUniqueField do
        use Oban.Worker, unique: [fields: [:unknown]]

        def perform(_), do: :ok
      end
    end

    assert_raise ArgumentError, ~r/unexpected unique options/, fn ->
      defmodule InvalidUniquePeriod do
        use Oban.Worker, unique: [period: 0]

        def perform(_), do: :ok
      end
    end

    assert_raise ArgumentError, ~r/unexpected unique options/, fn ->
      defmodule InvalidUniqueStates do
        use Oban.Worker, unique: [states: [:unknown]]

        def perform(_), do: :ok
      end
    end
  end
end
