defmodule Oban.JobTest do
  use Oban.Case, async: true

  doctest Oban.Job

  describe "new/2" do
    test "preventing the use of unknown options" do
      changeset = Job.new(%{}, workr: Fake)

      refute changeset.valid?
      assert {"unknown option :workr provided", _} = changeset.errors[:base]
    end
  end

  describe "scheduling with new/2" do
    test "scheduling a job for the future using :schedule_in" do
      changeset = Job.new(%{}, worker: Fake, schedule_in: 10)

      assert changeset.changes[:state] == "scheduled"
      assert changeset.changes[:scheduled_at]
    end

    property "scheduling a job for the future using a tuple" do
      now = DateTime.utc_now()

      check all schedule_in <- tuple({positive_integer(), time_unit()}) do
        assert %{changes: %{scheduled_at: %DateTime{} = scheduled_at, state: "scheduled"}} =
                 Job.new(%{}, worker: Fake, schedule_in: schedule_in)

        assert DateTime.compare(scheduled_at, now) == :gt
      end
    end

    test ":schedule_in does not accept other types of values" do
      assert Job.new(%{}, worker: Fake, schedule_in: true).errors[:schedule_in]
      assert Job.new(%{}, worker: Fake, schedule_in: "10").errors[:schedule_in]
      assert Job.new(%{}, worker: Fake, schedule_in: 0.12).errors[:schedule_in]
      assert Job.new(%{}, worker: Fake, schedule_in: {6, :units}).errors[:schedule_in]
      assert Job.new(%{}, worker: Fake, schedule_in: {6.0, :hours}).errors[:schedule_in]
    end
  end

  describe "tags with new/2" do
    test "normalizing and deduping tags" do
      tag_changes = fn tags ->
        Job.new(%{}, worker: Fake, tags: tags).changes[:tags]
      end

      refute tag_changes.(["", " ", "\n"])
      assert ["alpha"] = tag_changes.([" ", "\nalpha\n"])
      assert ["alpha"] = tag_changes.(["ALPHA", " alpha "])
      assert ["1", "2"] = tag_changes.([nil, 1, 2])
    end
  end

  describe "unique constraints with new/2" do
    test "marking a job as unique by setting the period provides defaults" do
      changeset = Job.new(%{}, worker: Fake, unique: [period: 60])

      assert changeset.changes[:unique] == %{
               fields: [:args, :queue, :worker],
               keys: [],
               period: 60,
               states: [:scheduled, :available, :executing, :retryable, :completed]
             }
    end

    test "overriding unique defaults" do
      changeset =
        Job.new(%{}, worker: Fake, unique: [fields: [:meta, :worker], states: [:available]])

      assert changeset.changes[:unique] == %{
               fields: [:meta, :worker],
               keys: [],
               period: 60,
               states: [:available]
             }
    end

    test ":unique does not accept other types of values or options" do
      assert Job.new(%{}, worker: Fake, unique: true).errors[:unique]
      assert Job.new(%{}, worker: Fake, unique: []).errors[:unique]
      assert Job.new(%{}, worker: Fake, unique: [special: :value]).errors[:unique]
      assert Job.new(%{}, worker: Fake, unique: [fields: [:bogus]]).errors[:unique]
      assert Job.new(%{}, worker: Fake, unique: [keys: [[]]]).errors[:unique]
      assert Job.new(%{}, worker: Fake, unique: [period: :bogus]).errors[:unique]
      assert Job.new(%{}, worker: Fake, unique: [states: [:random]]).errors[:unique]
    end
  end

  describe "replace options with new/2" do
    test "combining replace with legacy replace_args" do
      changes = fn opts ->
        Job.new(%{}, Keyword.put(opts, :worker, Fake)).changes[:replace]
      end

      assert [{:scheduled, [:args]} | _] = changes.(replace_args: true)
      assert [{:scheduled, [:tags]} | _] = changes.(replace: [:tags])
      assert [{:scheduled, [:args, :tags]} | _] = changes.(replace: [:tags], replace_args: true)
    end

    test "allows a subset of fields for replacement" do
      changes = fn replace ->
        Job.new(%{}, worker: Fake, replace: replace)
      end

      assert changes.([:args, :max_attempts, :meta, :priority]).valid?
      assert changes.([:queue, :scheduled_at, :tags, :worker]).valid?
      refute changes.([:state]).valid?
      refute changes.([:errors]).valid?
    end

    test "allows a list of state specific overrides" do
      changes = fn replace ->
        Job.new(%{}, worker: Fake, replace: replace)
      end

      for state <- Job.states() do
        changeset = changes.([{state, [:args]}])

        assert changeset.valid?
        assert [{^state, [:args]}] = changeset.changes[:replace]
      end

      refute changes.(sched: [:args]).valid?
      refute changes.(scheduled: [:state]).valid?
    end
  end

  describe "to_map/1" do
    @keys_with_defaults ~w(args attempt errors max_attempts meta queue state tags)a

    defp to_keys(opts) do
      %{}
      |> Job.new(opts)
      |> Job.to_map()
      |> Map.keys()
      |> Enum.sort()
    end

    defp default_keys_with(extra_keys) do
      (@keys_with_defaults ++ extra_keys) |> Enum.sort() |> Enum.uniq()
    end

    test "nil values are not retained" do
      assert to_keys([]) == @keys_with_defaults
      assert to_keys(worker: MyWorker) == default_keys_with([:worker])

      assert to_keys(schedule_in: 1, worker: MyWorker) ==
               default_keys_with([:scheduled_at, :worker])
    end

    test "retains all non-nil permitted attributes" do
      opts = [
        attempt: 1,
        attempted_by: ["foo"],
        attempted_at: DateTime.utc_now(),
        completed_at: DateTime.utc_now(),
        errors: [%{err: "baz"}],
        inserted_at: DateTime.utc_now(),
        max_attempts: 5,
        queue: "default",
        scheduled_at: DateTime.utc_now(),
        state: "scheduled",
        worker: "Fake"
      ]

      map =
        %{foo: "bar"}
        |> Job.new(opts)
        |> Job.to_map()

      assert %{foo: "bar"} == map[:args]

      for {key, val} <- opts, do: assert(map[key] == val)
    end
  end

  defp time_unit do
    one_of([:second, :seconds, :minute, :minutes, :hour, :hours, :day, :days, :week, :weeks])
  end
end
