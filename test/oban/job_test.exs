defmodule Oban.JobTest do
  use Oban.Case, async: true

  alias Ecto.Changeset

  doctest Oban.Job

  describe "new/2" do
    test "preventing the use of unknown options" do
      changeset = Job.new(%{}, workr: Fake)

      refute changeset.valid?
      assert {"unknown option :workr provided", _} = changeset.errors[:base]
    end

    test "validating priority values" do
      assert Job.new(%{}, priority: -1).errors[:priority]
      assert Job.new(%{}, priority: 10).errors[:priority]

      refute Job.new(%{}, priority: 0).errors[:priority]
      refute Job.new(%{}, priority: 9).errors[:priority]
    end

    test "validating max_attempt values" do
      assert Job.new(%{}, max_attempts: 0).errors[:max_attempts]
      refute Job.new(%{}, max_attempts: 1).errors[:max_attempts]
    end
  end

  describe "scheduling with new/2" do
    test "scheduling a job for the future using :schedule_in" do
      changeset = Job.new(%{}, worker: Fake, schedule_in: 10)

      assert changeset.changes[:state] == "scheduled"
      assert changeset.changes[:scheduled_at]
    end

    test "scheduling a job for the future using a time unit tuple" do
      now = DateTime.utc_now()

      for unit <- ~w(second seconds minute minutes hour hours day days week weeks)a do
        %{changes: changes} = Job.new(%{}, schedule_in: {1, unit})

        assert changes[:state] == "scheduled"
        assert changes[:scheduled_at]
        assert DateTime.compare(changes[:scheduled_at], now) == :gt
      end
    end

    test ":schedule_in does not accept other types of values" do
      assert Job.new(%{}, schedule_in: true).errors[:schedule_in]
      assert Job.new(%{}, schedule_in: "10").errors[:schedule_in]
      assert Job.new(%{}, schedule_in: 0.12).errors[:schedule_in]
      assert Job.new(%{}, schedule_in: {6, :units}).errors[:schedule_in]
      assert Job.new(%{}, schedule_in: {6.0, :hours}).errors[:schedule_in]
    end

    test "automatically setting the state to scheduled" do
      assert %{changes: %{state: "scheduled"}} = Job.new(%{}, schedule_in: 1)
      assert %{changes: %{state: "scheduled"}} = Job.new(%{}, schedule_in: 1, state: "available")
      assert %{changes: %{state: "completed"}} = Job.new(%{}, schedule_in: 1, state: "completed")
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

  describe "unique config with new/2" do
    test "marking a job unique for :infinity in all states by passing true" do
      changeset = Job.new(%{}, worker: Fake, unique: true)

      assert %{period: :infinity} = changeset.changes[:unique]
    end

    test "allowing unique with nil or false" do
      assert Job.new(%{}, worker: Fake, unique: nil).valid?
      assert Job.new(%{}, worker: Fake, unique: false).valid?
    end

    test "marking a job as unique by setting the period provides defaults" do
      changeset = Job.new(%{}, worker: Fake, unique: [period: 60])

      assert changeset.changes[:unique] == %{
               fields: [:args, :queue, :worker],
               keys: [],
               period: 60,
               states: ~w(scheduled available executing retryable completed)a,
               timestamp: :inserted_at
             }
    end

    test "merging custom options with the unique defaults" do
      changeset =
        Job.new(%{},
          worker: Fake,
          unique: [fields: [:meta, :worker], states: [:available], timestamp: :scheduled_at]
        )

      assert changeset.changes[:unique] == %{
               fields: [:meta, :worker],
               keys: [],
               period: 60,
               states: [:available],
               timestamp: :scheduled_at
             }
    end

    test "translating unique period with time units into seconds" do
      changeset = Job.new(%{}, worker: Fake, unique: [period: {1, :hour}])

      assert %{period: 3600} = changeset.changes[:unique]
    end

    test "rejecting unknown values or options" do
      assert Job.new(%{}, worker: Fake, unique: []).errors[:unique]
      assert Job.new(%{}, worker: Fake, unique: [special: :value]).errors[:unique]
      assert Job.new(%{}, worker: Fake, unique: [fields: [:bogus]]).errors[:unique]
      assert Job.new(%{}, worker: Fake, unique: [keys: [[]]]).errors[:unique]
      assert Job.new(%{}, worker: Fake, unique: [period: :bogus]).errors[:unique]
      assert Job.new(%{}, worker: Fake, unique: [period: {1, :bogus}]).errors[:unique]
      assert Job.new(%{}, worker: Fake, unique: [states: [:random]]).errors[:unique]
      assert Job.new(%{}, worker: Fake, unique: [timestamp: :updated_at]).errors[:unique]
    end

    test "ignoring empty keys when args or meta are missing in fields" do
      assert Job.new(%{}, worker: Fake, unique: [keys: [], fields: [:worker]]).valid?
    end

    test "unique keys are accepted with args or meta in fields" do
      assert Job.new(%{}, worker: Fake, unique: [keys: [:foo], fields: [:worker, :args]]).valid?
      assert Job.new(%{}, worker: Fake, unique: [keys: [:foo], fields: [:meta]]).valid?
    end

    test "unique keys are rejected without args or meta in fields" do
      refute Job.new(%{}, worker: Fake, unique: [keys: [:foo], fields: []]).valid?
      refute Job.new(%{}, worker: Fake, unique: [keys: [:foo], fields: [:worker]]).valid?
      refute Job.new(%{}, worker: Fake, unique: [keys: [:foo], fields: [:worker, :queue]]).valid?
    end

    test "unique state groups are expanded into a list of states" do
      changeset = Job.new(%{}, unique: [states: :incomplete])

      assert ~w(suspended available scheduled executing retryable)a =
               changeset.changes.unique.states
    end
  end

  describe "warn_unique/1" do
    test "passing through non-list values" do
      assert :ok = Job.warn_unique(true)
      assert :ok = Job.warn_unique(false)
      assert :ok = Job.warn_unique(nil)
    end

    test "ignoring options without an explicit :states list" do
      assert :ok = Job.warn_unique(period: 60)
      assert :ok = Job.warn_unique(states: :all)
      assert :ok = Job.warn_unique(states: :incomplete)
      assert :ok = Job.warn_unique(states: :scheduled)
      assert :ok = Job.warn_unique(states: :successful)

      assert :ok = Job.warn_unique(states: [:scheduled])
    end

    test "warning when no insertion-landing state is listed" do
      assert {:warn, _} = Job.warn_unique(states: ~w(completed cancelled discarded)a)
      assert {:warn, _} = Job.warn_unique(states: [:completed])
      assert {:warn, _} = Job.warn_unique(states: [:executing])
      assert {:warn, _} = Job.warn_unique(states: [:retryable])
    end

    test "warning when in-flight states are partially listed" do
      assert {:warn, _} = Job.warn_unique(states: ~w(available executing scheduled)a)
      assert {:warn, _} = Job.warn_unique(states: ~w(available executing scheduled completed)a)
    end
  end

  describe "replace options with new/2" do
    test "combining replace with legacy replace_args" do
      changes = fn opts ->
        Job.new(%{}, Keyword.put(opts, :worker, Fake)).changes[:replace]
      end

      assert [{:suspended, [:args]} | _] = changes.(replace_args: true)
      assert [{:suspended, [:tags]} | _] = changes.(replace: [:tags])
      assert [{:suspended, [:args, :tags]} | _] = changes.(replace: [:tags], replace_args: true)
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

  describe "update/2" do
    test "setting the state when scheduled_at is provided" do
      job =
        %{}
        |> Job.new(worker: Fake)
        |> Changeset.apply_action!(:insert)

      assert "available" == job.state

      changeset = Job.update(job, %{scheduled_at: DateTime.utc_now()})

      assert %{state: "scheduled", scheduled_at: %{}} = changeset.changes
    end
  end

  describe "to_map/1" do
    test "retaining all non-nil permitted attributes" do
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
        tags: nil,
        worker: "Fake"
      ]

      map =
        %{foo: "bar"}
        |> Job.new(opts)
        |> Job.to_map()

      assert %{foo: "bar"} == map[:args]
      refute Map.has_key?(map, :tags)

      for {key, val} <- opts, do: assert(map[key] == val)
    end
  end

  describe "query/1" do
    defp all(filters) do
      filters
      |> Job.query()
      |> Repo.all()
    end

    test "filtering by id" do
      job_a = insert!(%{}, worker: Worker)
      _job_ = insert!(%{}, worker: Worker)
      job_c = insert!(%{}, worker: Worker)

      assert [_] = all(id: job_a.id)
      assert [_, _] = all(id: [job_a.id, job_c.id])
      assert [] = all(id: 1_000_000)
    end

    test "filtering by state" do
      insert!(%{}, worker: Worker, state: "available")
      insert!(%{}, worker: Worker, state: "completed")
      insert!(%{}, worker: Worker, state: "cancelled")

      assert [%Job{state: "available"}] = all(state: "available")
      assert [%Job{state: "available"}] = all(state: :available)

      assert [_, _] = all(state: ~w(completed cancelled))
      assert [_, _] = all(state: [:completed, :cancelled])
    end

    test "filtering by worker" do
      insert!(%{}, worker: MyApp.Alpha)
      insert!(%{}, worker: MyApp.Beta)
      insert!(%{}, worker: MyApp.Gamma)

      assert [%Job{worker: "MyApp.Alpha"}] = all(worker: MyApp.Alpha)
      assert [%Job{worker: "MyApp.Alpha"}] = all(worker: "MyApp.Alpha")

      assert [_, _] = all(worker: [MyApp.Alpha, MyApp.Beta])
      assert [_, _] = all(worker: ["MyApp.Alpha", "MyApp.Beta"])
    end

    test "filtering by queue" do
      insert!(%{}, worker: Worker, queue: "alpha")
      insert!(%{}, worker: Worker, queue: "beta")
      insert!(%{}, worker: Worker, queue: "gamma")

      assert [%Job{queue: "alpha"}] = all(queue: "alpha")
      assert [%Job{queue: "alpha"}] = all(queue: :alpha)
      assert [_, _] = all(queue: ~w(alpha beta))
    end

    test "filtering by priority" do
      insert!(%{}, worker: Worker, priority: 0)
      insert!(%{}, worker: Worker, priority: 5)
      insert!(%{}, worker: Worker, priority: 9)

      assert [%Job{priority: 0}] = all(priority: 0)
      assert [_, _] = all(priority: [0, 5])
      assert [] = all(priority: 3)
    end

    test "filtering by tags" do
      insert!(%{}, worker: Worker, tags: ["urgent"])
      insert!(%{}, worker: Worker, tags: ["urgent", "vip"])
      insert!(%{}, worker: Worker, tags: [])

      assert [%Job{tags: ["urgent"]}] = all(tags: ["urgent"])
      assert [%Job{tags: ["urgent", "vip"]}] = all(tags: ["urgent", "vip"])
      assert [%Job{tags: []}] = all(tags: [])
    end

    test "combining multiple filters" do
      insert!(%{}, worker: MyApp.Alpha, queue: "alpha", state: "completed")
      insert!(%{}, worker: MyApp.Alpha, queue: "alpha", state: "cancelled")
      insert!(%{}, worker: MyApp.Beta, queue: "alpha", state: "completed")

      assert [_, _] = all(worker: MyApp.Alpha, state: ~w(completed cancelled))
      assert [_] = all(worker: MyApp.Alpha, state: "completed", queue: "alpha")
    end

    test "composing with further Ecto.Query calls" do
      import Ecto.Query, only: [order_by: 2, limit: 2]

      insert!(%{}, worker: Worker, priority: 9)
      insert!(%{}, worker: Worker, priority: 1)
      insert!(%{}, worker: Worker, priority: 5)

      query =
        [priority: [1, 5, 9]]
        |> Job.query()
        |> order_by(asc: :priority)
        |> limit(2)

      assert [%Job{priority: 1}, %Job{priority: 5}] = Repo.all(query)
    end

    test "filtering by args containment" do
      insert!(%{account_id: 1, region: "us-east"}, worker: Worker)
      insert!(%{account_id: 1, region: "us-west"}, worker: Worker)
      insert!(%{account_id: 2, region: "us-east"}, worker: Worker)
      insert!(%{user: %{id: 42, role: "admin"}}, worker: Worker)

      assert [_, _] = all(args: %{account_id: 1})
      assert [_] = all(args: %{account_id: 1, region: "us-east"})
      assert [_] = all(args: %{user: %{id: 42}})
      assert [] = all(args: %{account_id: 99})
    end

    test "filtering by meta containment" do
      insert!(%{}, worker: Worker, meta: %{batch_id: "abc", priority: "high"})
      insert!(%{}, worker: Worker, meta: %{batch_id: "abc", priority: "low"})
      insert!(%{}, worker: Worker, meta: %{batch_id: "xyz"})

      assert [_, _] = all(meta: %{batch_id: "abc"})
      assert [_] = all(meta: %{batch_id: "abc", priority: "high"})
      assert [] = all(meta: %{batch_id: "none"})
    end

    test "combining args with other filters" do
      insert!(%{account_id: 1}, worker: Worker, state: "available")
      insert!(%{account_id: 1}, worker: Worker, state: "completed")
      insert!(%{account_id: 2}, worker: Worker, state: "available")

      assert [%Job{state: "available"}] = all(args: %{account_id: 1}, state: "available")
    end

    test "raising on unknown fields, nil values, and empty lists" do
      assert_raise ArgumentError, ~r/unknown filter field :foo/, fn ->
        Job.query(foo: "bar")
      end

      assert_raise ArgumentError, ~r/can't be nil/, fn ->
        Job.query(state: nil)
      end

      assert_raise ArgumentError, ~r/can't be an empty list/, fn ->
        Job.query(state: [])
      end

      assert_raise ArgumentError, ~r/can't be empty/, fn ->
        Job.query(args: %{})
      end

      assert_raise ArgumentError, ~r/must be a map/, fn ->
        Job.query(meta: [])
      end
    end
  end
end
