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
    test "nil values are not retained" do
      to_keys = fn opts ->
        %{}
        |> Job.new(opts)
        |> Job.to_map()
        |> Map.keys()
      end

      assert to_keys.([]) == [:args, :queue, :state]
      assert to_keys.(worker: MyWorker) == [:args, :queue, :state, :worker]

      assert to_keys.(schedule_in: 1, worker: MyWorker) == [
               :args,
               :queue,
               :scheduled_at,
               :state,
               :worker
             ]
    end
  end
end
