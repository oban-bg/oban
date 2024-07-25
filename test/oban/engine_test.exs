for engine <- [Oban.Engines.Basic, Oban.Engines.Lite] do
  defmodule Module.concat(engine, Test) do
    use Oban.Case, async: true

    alias Ecto.Adapters.SQL.Sandbox
    alias Ecto.Multi
    alias Oban.Engines.Lite
    alias Oban.{Notifier, TelemetryHandler}

    @engine engine
    @repo if engine == Lite, do: LiteRepo, else: Repo

    @moduletag lite: engine == Lite

    defmodule MiniUniq do
      use Oban.Worker, unique: [fields: [:args]]

      @impl Worker
      def perform(_job), do: :ok
    end

    describe "insert/2" do
      setup :start_supervised_oban

      test "inserting a single job", %{name: name} do
        TelemetryHandler.attach_events()

        assert {:ok, job} = Oban.insert(name, Worker.new(%{ref: 1}))

        assert_receive {:event, [:insert_job, :stop], _, %{job: ^job, opts: []}}
      end

      test "broadcasting an insert event", %{name: name} do
        Notifier.listen(name, :insert)

        Oban.insert(name, Worker.new(%{action: "OK", ref: 0}, queue: :alpha))
        Oban.insert(name, Worker.new(%{action: "OK", ref: 0}, queue: :gamma, schedule_in: 1))

        assert_received {:notification, :insert, %{"queue" => "alpha"}}
        refute_received {:notification, :insert, %{"queue" => "gamma"}}
      end

      @tag :unique
      test "inserting a job with uniqueness applied", %{name: name} do
        changeset = Worker.new(%{ref: 1}, unique: [period: 60])

        assert {:ok, job_1} = Oban.insert(name, changeset)
        assert {:ok, job_2} = Oban.insert(name, changeset)

        refute job_1.conflict?
        assert job_2.conflict?
        assert job_1.id == job_2.id
      end

      @tag unique: true, skip: @engine == Lite
      test "preventing duplicate jobs between processes", %{name: name} do
        parent = self()
        changeset = Worker.new(%{ref: 1}, unique: [period: 60])

        fun = fn ->
          Sandbox.allow(Repo, parent, self())

          {:ok, %Job{id: id, conflict?: conflict}} = Oban.insert(name, changeset)

          {id, conflict}
        end

        results =
          1..3
          |> Enum.map(fn _ -> Task.async(fun) end)
          |> Enum.map(&Task.await/1)

        assert 1 == results |> Enum.uniq_by(&elem(&1, 0)) |> length()
        assert [false, true, true] == results |> Enum.map(&elem(&1, 1)) |> Enum.sort()
      end

      @tag :unique
      test "scoping uniqueness to specific fields", %{name: name} do
        changeset1 = Job.new(%{}, worker: "A", unique: [fields: [:worker]])
        changeset2 = Job.new(%{}, worker: "B", unique: [fields: [:worker]])

        assert {:ok, job_1} = Oban.insert(name, changeset1)
        assert {:ok, job_2} = Oban.insert(name, changeset2)
        assert {:ok, job_3} = Oban.insert(name, changeset1)

        refute job_1.conflict?
        refute job_2.conflict?
        assert job_3.conflict?
        assert job_1.id == job_3.id
      end

      @tag :unique
      test "scoping uniqueness to specific argument keys", %{name: name} do
        changeset1 = Worker.new(%{id: 1, xd: 1}, unique: [keys: [:id]])
        changeset2 = Worker.new(%{id: 2, xd: 2}, unique: [keys: [:id]])
        changeset3 = Worker.new(%{id: 3, xd: 1}, unique: [keys: [:xd]])
        changeset4 = Worker.new(%{id: 1, xd: 3}, unique: [keys: [:id]])

        assert {:ok, job_1} = Oban.insert(name, changeset1)
        assert {:ok, job_2} = Oban.insert(name, changeset2)
        assert {:ok, job_3} = Oban.insert(name, changeset3)
        assert {:ok, job_4} = Oban.insert(name, changeset4)

        refute job_1.conflict?
        refute job_2.conflict?
        assert job_3.conflict?
        assert job_4.conflict?

        assert job_1.id == job_3.id
        assert job_1.id == job_4.id
      end

      @tag :unique
      test "considering empty args distinct from non-empty args", %{name: name} do
        changeset1 = MiniUniq.new(%{id: 1})
        changeset2 = MiniUniq.new(%{})

        assert {:ok, %Job{id: id_1}} = Oban.insert(name, changeset1)
        assert {:ok, %Job{id: id_2}} = Oban.insert(name, changeset2)
        assert {:ok, %Job{id: id_3}} = Oban.insert(name, changeset2)

        assert id_1 != id_2
        assert id_2 == id_3
      end

      @tag :unique
      test "considering all args to establish uniqueness", %{name: name} do
        changeset1 = MiniUniq.new(%{id: 1})
        changeset2 = MiniUniq.new(%{id: 1, extra: :cool_beans})

        assert {:ok, %Job{id: id_1}} = Oban.insert(name, changeset1)
        assert {:ok, %Job{id: id_2}} = Oban.insert(name, changeset2)

        assert id_1 != id_2

        changeset3 = MiniUniq.new(%{id: 2, extra: :cool_beans})
        changeset4 = MiniUniq.new(%{id: 2})

        assert {:ok, %Job{id: id_1}} = Oban.insert(name, changeset3)
        assert {:ok, %Job{id: id_2}} = Oban.insert(name, changeset4)

        assert id_1 != id_2
      end

      @tag :unique
      test "scoping uniqueness by specific meta keys", %{name: name} do
        unique = [fields: [:meta], keys: [:slug]]

        changeset1 = Worker.new(%{}, meta: %{slug: "abc123"}, unique: unique)
        changeset2 = Worker.new(%{}, meta: %{slug: "def456"}, unique: unique)

        assert {:ok, %Job{id: id_1}} = Oban.insert(name, changeset1)
        assert {:ok, %Job{id: id_2}} = Oban.insert(name, changeset2)

        assert {:ok, %Job{id: ^id_1}} = Oban.insert(name, changeset1)
        assert {:ok, %Job{id: ^id_2}} = Oban.insert(name, changeset2)
      end

      @tag :unique
      test "scoping uniqueness by state", %{name: name} do
        %Job{id: id_1} = insert!(name, %{id: 1}, state: "available")
        %Job{id: id_2} = insert!(name, %{id: 2}, state: "completed")
        %Job{id: id_3} = insert!(name, %{id: 3}, state: "executing")
        %Job{id: id_4} = insert!(name, %{id: 4}, state: "discarded")

        uniq_insert = fn args, states ->
          Oban.insert(name, Worker.new(args, unique: [states: states]))
        end

        assert {:ok, %{id: ^id_1}} = uniq_insert.(%{id: 1}, [:available])
        assert {:ok, %{id: ^id_2}} = uniq_insert.(%{id: 2}, [:available, :completed])
        assert {:ok, %{id: ^id_2}} = uniq_insert.(%{id: 2}, [:completed, :discarded])
        assert {:ok, %{id: ^id_3}} = uniq_insert.(%{id: 3}, [:completed, :executing])
        assert {:ok, %{id: ^id_4}} = uniq_insert.(%{id: 4}, [:completed, :discarded])
      end

      @tag :unique
      test "scoping uniqueness by period", %{name: name} do
        four_minutes_ago = seconds_ago(240)
        five_minutes_ago = seconds_ago(300)
        nine_minutes_ago = seconds_ago(540)

        uniq_insert = fn args, period ->
          Oban.insert(name, Worker.new(args, unique: [period: period]))
        end

        job_1 = insert!(name, %{id: 1}, inserted_at: four_minutes_ago)
        job_2 = insert!(name, %{id: 2}, inserted_at: five_minutes_ago)
        job_3 = insert!(name, %{id: 3}, inserted_at: nine_minutes_ago)

        assert {:ok, job_4} = uniq_insert.(%{id: 1}, 239)
        assert {:ok, job_5} = uniq_insert.(%{id: 2}, 299)
        assert {:ok, job_6} = uniq_insert.(%{id: 3}, 539)

        assert job_1.id != job_4.id
        assert job_2.id != job_5.id
        assert job_3.id != job_6.id

        assert {:ok, job_7} = uniq_insert.(%{id: 1}, 241)
        assert {:ok, job_8} = uniq_insert.(%{id: 2}, 300)
        assert {:ok, job_9} = uniq_insert.(%{id: 3}, :infinity)

        assert job_7.id in [job_1.id, job_4.id]
        assert job_8.id in [job_2.id, job_5.id]
        assert job_9.id in [job_3.id, job_6.id]
      end

      @tag :unique
      test "scoping uniqueness by period compared to the scheduled time", %{name: name} do
        job_1 = insert!(name, %{id: 1}, scheduled_at: seconds_ago(120))

        uniq_insert = fn args, period, timestamp ->
          Oban.insert(name, Worker.new(args, unique: [period: period, timestamp: timestamp]))
        end

        assert {:ok, job_2} = uniq_insert.(%{id: 1}, 121, :scheduled_at)
        assert {:ok, job_3} = uniq_insert.(%{id: 1}, 119, :scheduled_at)

        assert job_1.id == job_2.id
        assert job_1.id != job_3.id
      end

      @tag :unique
      test "replacing fields on unique conflict", %{name: name} do
        four_seconds = seconds_from_now(4)
        five_seconds = seconds_from_now(5)

        replace = fn opts ->
          opts =
            Keyword.merge(opts,
              replace: [:scheduled_at, :priority],
              unique: [keys: [:id]]
            )

          Oban.insert(name, Worker.new(%{id: 1}, opts))
        end

        assert {:ok, job_1} = replace.(priority: 3, scheduled_at: four_seconds)
        assert {:ok, job_2} = replace.(priority: 2, scheduled_at: five_seconds)

        assert job_1.id == job_2.id
        assert job_1.scheduled_at == four_seconds
        assert job_2.scheduled_at == five_seconds
        assert job_1.priority == 3
        assert job_2.priority == 2
      end

      @tag :unique
      test "replacing fields based on job state", %{name: name} do
        replace = fn args, opts ->
          opts =
            Keyword.merge(opts,
              replace: [scheduled: [:priority]],
              unique: [keys: [:id]]
            )

          Oban.insert(name, Worker.new(args, opts))
        end

        assert {:ok, job_1} = replace.(%{id: 1}, priority: 1, state: "scheduled")
        assert {:ok, job_2} = replace.(%{id: 2}, priority: 1, state: "executing")
        assert {:ok, job_3} = replace.(%{id: 1}, priority: 2)
        assert {:ok, job_4} = replace.(%{id: 2}, priority: 2)

        assert job_1.id == job_3.id
        assert job_2.id == job_4.id
        assert job_3.priority == 2
        assert job_4.priority == 1
      end
    end

    describe "insert/4" do
      setup :start_supervised_oban

      test "inserting multiple jobs within a multi", %{name: name} do
        TelemetryHandler.attach_events()

        multi = Multi.new()
        multi = Oban.insert(name, multi, :job_1, Worker.new(%{ref: 1}))
        multi = Oban.insert(name, multi, "job-2", fn _ -> Worker.new(%{ref: 2}) end)
        multi = Oban.insert(name, multi, {:job, 3}, Worker.new(%{ref: 3}))
        assert {:ok, results} = @repo.transaction(multi)

        assert %{:job_1 => job_1, "job-2" => job_2, {:job, 3} => job_3} = results

        assert job_1.id
        assert job_2.id
        assert job_3.id

        assert_receive {:event, [:insert_job, :stop], _, %{job: ^job_1, opts: []}}
        assert_receive {:event, [:insert_job, :stop], _, %{job: ^job_2, opts: []}}
        assert_receive {:event, [:insert_job, :stop], _, %{job: ^job_3, opts: []}}
      end

      @tag :unique
      test "inserting unique jobs within a multi transaction", %{name: name} do
        multi = Multi.new()
        multi = Oban.insert(name, multi, :j1, Worker.new(%{id: 1}, unique: [period: 30]))
        multi = Oban.insert(name, multi, :j2, Worker.new(%{id: 2}, unique: [period: 30]))
        multi = Oban.insert(name, multi, :j3, Worker.new(%{id: 1}, unique: [period: 30]))

        assert {:ok, %{j1: job_1, j2: job_2, j3: job_3}} = @repo.transaction(multi)

        assert job_1.id != job_2.id
        assert job_1.id == job_3.id
      end
    end

    describe "insert!/2" do
      setup :start_supervised_oban

      test "inserting a single job", %{name: name} do
        assert %Job{} = Oban.insert!(name, Worker.new(%{ref: 1}))
      end

      test "raising a changeset error when inserting fails", %{name: name} do
        assert_raise Ecto.InvalidChangesetError, fn ->
          Oban.insert!(name, Worker.new(%{ref: 1}, priority: -1))
        end
      end
    end

    describe "insert_all/2" do
      setup :start_supervised_oban

      test "inserting multiple jobs", %{name: name} do
        TelemetryHandler.attach_events()

        changesets = Enum.map(0..2, &Worker.new(%{ref: &1}, queue: "special", schedule_in: 10))
        jobs = Oban.insert_all(name, changesets)

        assert is_list(jobs)
        assert length(jobs) == 3

        [%Job{queue: "special", state: "scheduled"} = job | _] = jobs

        assert job.id
        assert job.args
        assert job.scheduled_at

        assert_receive {:event, [:insert_all_jobs, :stop], _, %{jobs: _, opts: []}}
      end

      test "inserting multiple jobs with a stream", %{name: name} do
        changesets = Stream.map(0..1, &Worker.new(%{ref: &1}))

        [_job_1, _job_2] = Oban.insert_all(name, changesets)
      end

      test "inserting multiple jobs from a changeset wrapper", %{name: name} do
        changesets = [Worker.new(%{ref: 0}), Worker.new(%{ref: 1})]

        [_job_1, _job_2] = Oban.insert_all(name, %{changesets: changesets})
      end

      test "inserting multiple jobs from a changeset wrapped stream", %{name: name} do
        changesets = Stream.map(0..1, &Worker.new(%{ref: &1}))
        changesets = Stream.concat(changesets, changesets)

        [_ | _] = Oban.insert_all(name, %{changesets: changesets})
      end

      test "handling empty changesets list from a wrapper", %{name: name} do
        assert [] = Oban.insert_all(name, %{changesets: []})
      end

      test "inserting jobs with an invalid changeset raises an exception", %{name: name} do
        changesets = [Worker.new(%{ref: 0}), Worker.new(%{ref: 1}, priority: -1)]

        assert_raise Ecto.InvalidChangesetError, fn ->
          Oban.insert_all(name, changesets)
        end
      end

      test "broadcasting an insert event for all queues", %{name: name} do
        Notifier.listen(name, :insert)

        Oban.insert_all(name, [
          Worker.new(%{action: "OK", ref: 1}, queue: :gamma),
          Worker.new(%{action: "OK", ref: 2}, queue: :gamma),
          Worker.new(%{action: "OK", ref: 3}, queue: :delta)
        ])

        assert_receive {:notification, :insert, %{"queue" => "gamma"}}
        assert_receive {:notification, :insert, %{"queue" => "delta"}}
      end
    end

    describe "insert_all/3" do
      setup :start_supervised_oban

      test "inserting multiple jobs with additional options", %{name: name} do
        assert [%Job{}] = Oban.insert_all(name, [Worker.new(%{ref: 0})], timeout: 1_000)
      end
    end

    describe "insert_all/4" do
      setup :start_supervised_oban

      test "inserting multiple jobs within a multi", %{name: name} do
        TelemetryHandler.attach_events()

        changesets_1 = Enum.map(1..2, &Worker.new(%{ref: &1}))
        changesets_2 = Enum.map(3..4, &Worker.new(%{ref: &1}))
        changesets_3 = Enum.map(5..6, &Worker.new(%{ref: &1}))

        multi = Multi.new()
        multi = Oban.insert_all(name, multi, "jobs-1", changesets_1)
        multi = Oban.insert_all(name, multi, "jobs-2", changesets_2)
        multi = Multi.run(multi, "build-jobs-3", fn _, _ -> {:ok, changesets_3} end)
        multi = Oban.insert_all(name, multi, "jobs-3", & &1["build-jobs-3"])

        {:ok, %{"jobs-1" => jobs_1, "jobs-2" => jobs_2, "jobs-3" => jobs_3}} =
          @repo.transaction(multi)

        assert [%Job{}, %Job{}] = jobs_1
        assert [%Job{}, %Job{}] = jobs_2
        assert [%Job{}, %Job{}] = jobs_3

        assert_receive {:event, [:insert_all_jobs, :stop], _, %{jobs: _, opts: []}}
      end

      test "inserting multiple jobs from a changeset wrapper", %{name: name} do
        wrap = %{changesets: [Worker.new(%{ref: 0})]}

        multi = Multi.new()
        multi = Oban.insert_all(name, multi, "jobs-1", wrap)
        multi = Oban.insert_all(name, multi, "jobs-2", fn _ -> wrap end)

        {:ok, %{"jobs-1" => [_job_1], "jobs-2" => [_job_2]}} = @repo.transaction(multi)
      end

      test "handling empty changesets list from wrapper", %{name: name} do
        assert {:ok, %{jobs: []}} =
                 name
                 |> Oban.insert_all(Multi.new(), :jobs, %{changesets: []})
                 |> @repo.transaction()
      end
    end

    describe "prune_jobs/3" do
      setup :start_supervised_oban

      test "deleting jobs in prunable states", %{name: name} do
        TelemetryHandler.attach_events(span_type: [:job, [:engine, :prune_jobs]])

        for state <- Job.states(), seconds <- 59..61 do
          opts = [state: to_string(state), scheduled_at: seconds_ago(seconds)]

          # Insert one job at a time to avoid a "Cell-wise defaults" error in SQLite.
          Oban.insert!(name, Worker.new(%{}, opts))
        end

        {:ok, jobs} =
          name
          |> Oban.config()
          |> Oban.Engine.prune_jobs(Job, limit: 100, max_age: 60)

        assert 6 == length(jobs)

        assert ~w(cancelled completed discarded) =
                 jobs
                 |> Enum.map(& &1.state)
                 |> Enum.uniq()
                 |> Enum.sort()

        assert_receive {:event, [:prune_jobs, :stop], _, %{jobs: ^jobs}}
      end
    end

    describe "cancel_job/2" do
      setup :start_supervised_oban

      @describetag oban_opts: [queues: [alpha: 5], stage_interval: 10, testing: :disabled]

      test "cancelling an executing job", %{name: name} do
        TelemetryHandler.attach_events(span_type: [:job, [:engine, :cancel_job]])

        job = insert!(name, %{ref: 1, sleep: 100}, [])

        assert_receive {:started, 1}

        Oban.cancel_job(name, job)

        refute_receive {:ok, 1}

        assert %Job{state: "cancelled", errors: [_], cancelled_at: %_{}} = reload(name, job)
        assert %{running: []} = Oban.check_queue(name, queue: :alpha)

        assert_receive {:event, :stop, _, %{job: _}}
        assert_receive {:event, [:cancel_job, :stop], _, %{job: _}}
      end

      test "cancelling jobs that may or may not be executing", %{name: name} do
        job_1 = insert!(name, %{ref: 1}, schedule_in: 10)
        job_2 = insert!(name, %{ref: 2}, schedule_in: 10, state: "retryable")
        job_3 = insert!(name, %{ref: 3}, state: "completed")
        job_4 = insert!(name, %{ref: 4, sleep: 100}, [])

        assert_receive {:started, 4}

        assert :ok = Oban.cancel_job(name, job_1.id)
        assert :ok = Oban.cancel_job(name, job_2.id)
        assert :ok = Oban.cancel_job(name, job_3.id)
        assert :ok = Oban.cancel_job(name, job_4.id)

        refute_receive {:ok, 4}

        assert %Job{state: "cancelled", errors: [], cancelled_at: %_{}} = reload(name, job_1)
        assert %Job{state: "cancelled", errors: [], cancelled_at: %_{}} = reload(name, job_2)
        assert %Job{state: "completed", errors: [], cancelled_at: nil} = reload(name, job_3)
        assert %Job{state: "cancelled", errors: [_], cancelled_at: %_{}} = reload(name, job_4)
      end
    end

    describe "cancel_all_jobs/2" do
      setup :start_supervised_oban

      @describetag oban_opts: [queues: [alpha: 5], stage_interval: 10, testing: :disabled]

      test "cancelling all jobs that may or may not be executing", %{name: name} do
        TelemetryHandler.attach_events(span_type: [:job, [:engine, :cancel_all_jobs]])

        job_1 = insert!(name, %{ref: 1}, schedule_in: 10)
        job_2 = insert!(name, %{ref: 2}, schedule_in: 10, state: "retryable")
        job_3 = insert!(name, %{ref: 3}, state: "completed")
        job_4 = insert!(name, %{ref: 4, sleep: 100}, [])

        assert_receive {:started, 4}

        assert {:ok, 3} = Oban.cancel_all_jobs(name, Job)

        refute_receive {:ok, 4}

        assert %Job{state: "cancelled", errors: [], cancelled_at: %_{}} = reload(name, job_1)
        assert %Job{state: "cancelled", errors: [], cancelled_at: %_{}} = reload(name, job_2)
        assert %Job{state: "completed", errors: [], cancelled_at: nil} = reload(name, job_3)
        assert %Job{state: "cancelled", errors: [_], cancelled_at: %_{}} = reload(name, job_4)

        assert_receive {:event, :stop, _, %{job: _}}
        assert_receive {:event, [:cancel_all_jobs, :stop], _, %{jobs: _jobs}}
      end
    end

    describe "retry_job/2" do
      setup :start_supervised_oban

      test "retrying jobs from multiple states", %{name: name} do
        job_1 = insert!(name, %{ref: 1}, state: "discarded", max_attempts: 20, attempt: 20)
        job_2 = insert!(name, %{ref: 2}, state: "completed", max_attempts: 20)
        job_3 = insert!(name, %{ref: 3}, state: "available", max_attempts: 20)
        job_4 = insert!(name, %{ref: 4}, state: "retryable", max_attempts: 20)
        job_5 = insert!(name, %{ref: 5}, state: "executing", max_attempts: 1, attempt: 1)

        assert :ok = Oban.retry_job(name, job_1)
        assert :ok = Oban.retry_job(name, job_2)
        assert :ok = Oban.retry_job(name, job_3)
        assert :ok = Oban.retry_job(name, job_4.id)
        assert :ok = Oban.retry_job(name, job_5.id)

        assert %Job{state: "available", max_attempts: 21} = reload(name, job_1)
        assert %Job{state: "available", max_attempts: 20} = reload(name, job_2)
        assert %Job{state: "available", max_attempts: 20} = reload(name, job_3)
        assert %Job{state: "available", max_attempts: 20} = reload(name, job_4)
        assert %Job{state: "executing", max_attempts: 1} = reload(name, job_5)
      end
    end

    describe "retry_all_jobs/2" do
      setup :start_supervised_oban

      test "retrying all retryable jobs", %{name: name} do
        TelemetryHandler.attach_events(span_type: [[:engine, :retry_all_jobs]])

        job_1 = insert!(name, %{ref: 1}, state: "discarded", max_attempts: 20, attempt: 20)
        job_2 = insert!(name, %{ref: 2}, state: "completed", max_attempts: 20)
        job_3 = insert!(name, %{ref: 3}, state: "available", max_attempts: 20)
        job_4 = insert!(name, %{ref: 4}, state: "retryable", max_attempts: 20)

        assert {:ok, 3} = Oban.retry_all_jobs(name, Job)

        assert %Job{state: "available", max_attempts: 21} = reload(name, job_1)
        assert %Job{state: "available", max_attempts: 20} = reload(name, job_2)
        assert %Job{state: "available", max_attempts: 20} = reload(name, job_3)
        assert %Job{state: "available", max_attempts: 20} = reload(name, job_4)

        assert_receive {:event, [:retry_all_jobs, :stop], _, %{jobs: _}}
      end
    end

    describe "integration" do
      setup :start_supervised_oban

      @describetag oban_opts: [queues: [alpha: 3], stage_interval: 10, testing: :disabled]

      test "inserting and executing jobs", %{name: name} do
        TelemetryHandler.attach_events()

        changesets =
          ~w(OK CANCEL DISCARD ERROR SNOOZE)
          |> Enum.with_index(1)
          |> Enum.map(fn {act, ref} -> Worker.new(%{action: act, ref: ref}) end)

        [job_1, job_2, job_3, job_4, job_5] = Oban.insert_all(name, changesets)

        assert_receive {:event, [:fetch_jobs, :stop], _, %{jobs: _}}

        assert_receive {:ok, 1}
        assert_receive {:cancel, 2}
        assert_receive {:discard, 3}
        assert_receive {:error, 4}
        assert_receive {:snooze, 5}

        with_backoff(fn ->
          assert %{state: "completed", completed_at: %_{}} = reload(name, job_1)
          assert %{state: "cancelled", cancelled_at: %_{}} = reload(name, job_2)
          assert %{state: "discarded", discarded_at: %_{}} = reload(name, job_3)
          assert %{state: "retryable", scheduled_at: %_{}} = reload(name, job_4)
          assert %{state: "scheduled", scheduled_at: %_{}} = reload(name, job_5)
        end)
      end

      @tag :capture_log
      test "safely executing jobs with any type of exit", %{name: name} do
        changesets =
          ~w(EXIT KILL TASK_ERROR TASK_EXIT)
          |> Enum.with_index(1)
          |> Enum.map(fn {act, ref} -> Worker.new(%{action: act, ref: ref}) end)

        jobs = Oban.insert_all(name, changesets)

        assert_receive {:exit, 1}
        assert_receive {:kill, 2}
        assert_receive {:async, 3}
        assert_receive {:async, 4}

        with_backoff(fn ->
          for job <- jobs do
            assert %{state: "retryable", errors: errors, scheduled_at: %_{}} = reload(name, job)
            assert [%{"attempt" => 1, "at" => _, "error" => _}] = errors
          end
        end)
      end

      test "executing jobs scheduled on or before the current time", %{name: name} do
        Oban.insert_all(name, [
          Worker.new(%{action: "OK", ref: 1}, schedule_in: -2),
          Worker.new(%{action: "OK", ref: 2}, schedule_in: -1),
          Worker.new(%{action: "OK", ref: 3}, schedule_in: 1)
        ])

        assert_receive {:ok, 1}
        assert_receive {:ok, 2}
        refute_receive {:ok, 3}
      end

      test "executing jobs in order of priority", %{name: name} do
        Oban.insert_all(name, [
          Worker.new(%{action: "OK", ref: 1}, priority: 3),
          Worker.new(%{action: "OK", ref: 2}, priority: 2),
          Worker.new(%{action: "OK", ref: 3}, priority: 1),
          Worker.new(%{action: "OK", ref: 4}, priority: 0)
        ])

        assert_receive {:ok, 1}
        assert_received {:ok, 2}
        assert_received {:ok, 3}
        assert_received {:ok, 4}
      end

      test "discarding jobs that exceed max attempts", %{name: name} do
        [job_1, job_2] =
          Oban.insert_all(name, [
            Worker.new(%{action: "ERROR", ref: 1}, max_attempts: 1),
            Worker.new(%{action: "ERROR", ref: 2}, max_attempts: 2)
          ])

        assert_receive {:error, 1}
        assert_receive {:error, 2}

        with_backoff(fn ->
          assert %{state: "discarded", discarded_at: %_{}} = reload(name, job_1)
          assert %{state: "retryable", scheduled_at: %_{}} = reload(name, job_2)
        end)
      end

      test "failing jobs that exceed the worker's timeout", %{name: name} do
        job = insert!(name, %{ref: 1, sleep: 20, timeout: 5}, [])

        assert_receive {:started, 1}
        refute_receive {:ok, 1}, 20

        assert %Job{state: "retryable", errors: [%{"error" => error}]} = reload(name, job)
        assert error == "** (Oban.TimeoutError) Oban.Integration.Worker timed out after 5ms"
      end

      test "applying custom backoff after uncaught exits", %{name: name} do
        job = insert!(name, %{ref: 1, backoff: 1, sleep: 20, timeout: 1}, attempt: 10)

        assert_receive {:started, 1}

        with_backoff(fn ->
          assert %Job{state: "retryable", scheduled_at: scheduled_at} = reload(name, job)

          assert_in_delta 1, DateTime.diff(scheduled_at, DateTime.utc_now()), 1
        end)
      end
    end

    # Helpers

    defp reload(name, job) do
      name
      |> Oban.config()
      |> Oban.Repo.reload(job)
    end

    defp start_supervised_oban(context) do
      name =
        context
        |> Map.get(:oban_opts, [])
        |> Keyword.put_new(:engine, @engine)
        |> Keyword.put_new(:repo, @repo)
        |> Keyword.put_new(:testing, :manual)
        |> start_supervised_oban!()

      {:ok, name: name}
    end
  end
end
