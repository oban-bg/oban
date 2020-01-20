defmodule Oban.JobTest do
  use Oban.Case, async: true

  describe "scheduling with new/2" do
    test "scheduling a job for the future using :schedule_in" do
      changeset = Job.new(%{}, worker: Fake, schedule_in: 10)

      assert changeset.changes[:state] == "scheduled"
      assert changeset.changes[:scheduled_at]
    end

    test ":schedule_in does not accept other types of values" do
      assert Job.new(%{}, worker: Fake, schedule_in: true).errors[:schedule_in]
      assert Job.new(%{}, worker: Fake, schedule_in: "10").errors[:schedule_in]
      assert Job.new(%{}, worker: Fake, schedule_in: 0.12).errors[:schedule_in]
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
               period: 60,
               states: [:available, :scheduled, :executing, :retryable, :completed]
             }
    end

    test "overriding unique defaults" do
      changeset = Job.new(%{}, worker: Fake, unique: [fields: [:worker], states: [:available]])

      assert changeset.changes[:unique] == %{
               fields: [:worker],
               period: 60,
               states: [:available]
             }
    end

    test ":unique does not accept other types of values or options" do
      assert Job.new(%{}, worker: Fake, unique: true).errors[:unique]
      assert Job.new(%{}, worker: Fake, unique: []).errors[:unique]
      assert Job.new(%{}, worker: Fake, unique: [special: :value]).errors[:unique]
      assert Job.new(%{}, worker: Fake, unique: [fields: [:bogus]]).errors[:unique]
      assert Job.new(%{}, worker: Fake, unique: [period: :infinity]).errors[:unique]
      assert Job.new(%{}, worker: Fake, unique: [states: [:random]]).errors[:unique]
    end
  end

  describe "to_map/1" do
    @keys_with_defaults ~w(args attempt errors max_attempts priority queue state tags)a

    defp to_keys(opts) do
      %{}
      |> Job.new(opts)
      |> Job.to_map()
      |> Map.keys()
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
      attrs = [
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

      map = %{foo: "bar"} |> Job.new(attrs) |> Job.to_map()
      assert map[:args] == %{foo: "bar"}
      Enum.each(attrs, fn {key, val} -> assert map[key] == val end)
    end
  end
end
