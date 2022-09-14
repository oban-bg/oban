defmodule ObanTest do
  use Oban.Case, async: true

  alias Ecto.Adapters.SQL.Sandbox
  alias Ecto.Multi
  alias Oban.Registry

  @opts [repo: Repo, testing: :manual]

  describe "child_spec/1" do
    test "name is used as a default child id" do
      assert Supervisor.child_spec(Oban, []).id == Oban
      assert Supervisor.child_spec({Oban, name: :foo}, []).id == :foo
    end
  end

  describe "start_link/1" do
    test "name can be an arbitrary term" do
      opts = Keyword.put(@opts, :name, make_ref())

      assert {:ok, _} = start_supervised({Oban, opts})
    end

    test "name defaults to `Oban`" do
      assert {:ok, pid} = start_supervised({Oban, @opts})
      assert Oban.whereis(Oban) == pid
    end

    test "name must be unique" do
      name = make_ref()
      opts = Keyword.put(@opts, :name, name)

      {:ok, pid} = Oban.start_link(opts)
      {:error, {:already_started, ^pid}} = Oban.start_link(opts)
    end
  end

  describe "insert/2" do
    setup :start_supervised_oban

    test "inserting a single job" do
      name = start_supervised_oban!(testing: :manual)

      assert {:ok, %Job{}} = Oban.insert(name, Worker.new(%{ref: 1}))
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

    @tag :unique
    test "preventing duplicate jobs between processes", %{name: name} do
      parent = self()
      changeset = Worker.new(%{ref: 1}, unique: [period: 60])

      fun = fn ->
        Sandbox.allow(Repo, parent, self())

        {:ok, %Job{id: id}} = Oban.insert(name, changeset)

        id
      end

      ids =
        1..3
        |> Enum.map(fn _ -> Task.async(fun) end)
        |> Enum.map(&Task.await/1)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()

      assert 1 == length(ids)
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
      defmodule MiniUniq do
        use Oban.Worker, unique: [fields: [:args]]

        @impl Worker
        def perform(_job), do: :ok
      end

      changeset1 = MiniUniq.new(%{id: 1})
      changeset2 = MiniUniq.new(%{})

      assert {:ok, %Job{id: id_1}} = Oban.insert(name, changeset1)
      assert {:ok, %Job{id: id_2}} = Oban.insert(name, changeset2)
      assert {:ok, %Job{id: id_3}} = Oban.insert(name, changeset2)

      assert id_1 != id_2
      assert id_2 == id_3
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
      %Job{id: id_1} = insert!(%{id: 1}, state: "available")
      %Job{id: id_2} = insert!(%{id: 2}, state: "completed")
      %Job{id: id_3} = insert!(%{id: 3}, state: "executing")
      %Job{id: id_4} = insert!(%{id: 4}, state: "discarded")

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

      job_1 = insert!(%{id: 1}, inserted_at: four_minutes_ago)
      job_2 = insert!(%{id: 2}, inserted_at: five_minutes_ago)
      job_3 = insert!(%{id: 3}, inserted_at: nine_minutes_ago)

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

    @tag oban_opts: [prefix: "private"]
    test "inserting jobs with a custom prefix", %{name: name} do
      insert!(name, %{ref: 1, action: "OK"}, [])

      assert [%Job{}] = Repo.all(Job, prefix: "private")
    end

    @tag oban_opts: [prefix: "private"]
    test "inserting unique jobs with a custom prefix", %{name: name} do
      opts = [unique: [period: 60, fields: [:worker]]]

      insert!(name, %{ref: 1, action: "OK"}, opts)
      insert!(name, %{ref: 2, action: "OK"}, opts)

      assert [%Job{args: %{"ref" => 1}}] = Repo.all(Job, prefix: "private")
    end
  end

  describe "insert/4" do
    setup :start_supervised_oban

    test "inserting multiple jobs within a multi", %{name: name} do
      multi = Multi.new()
      multi = Oban.insert(name, multi, :job_1, Worker.new(%{ref: 1}))
      multi = Oban.insert(name, multi, "job-2", fn _ -> Worker.new(%{ref: 2}) end)
      multi = Oban.insert(name, multi, {:job, 3}, Worker.new(%{ref: 3}))
      assert {:ok, results} = Repo.transaction(multi)

      assert %{:job_1 => job_1, "job-2" => job_2, {:job, 3} => job_3} = results

      assert job_1.id
      assert job_2.id
      assert job_3.id
    end

    @tag :unique
    test "inserting unique jobs within a multi transaction", %{name: name} do
      multi = Multi.new()
      multi = Oban.insert(name, multi, :j1, Worker.new(%{id: 1}, unique: [period: 30]))
      multi = Oban.insert(name, multi, :j2, Worker.new(%{id: 2}, unique: [period: 30]))
      multi = Oban.insert(name, multi, :j3, Worker.new(%{id: 1}, unique: [period: 30]))

      assert {:ok, %{j1: job_1, j2: job_2, j3: job_3}} = Repo.transaction(multi)

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
      changesets = Enum.map(0..2, &Worker.new(%{ref: &1}, queue: "special", schedule_in: 10))
      jobs = Oban.insert_all(name, changesets)

      assert is_list(jobs)
      assert length(jobs) == 3

      [%Job{queue: "special", state: "scheduled"} = job | _] = jobs

      assert job.id
      assert job.args
      assert job.scheduled_at
    end

    test "inserting multiple jobs from a changeset wrapper", %{name: name} do
      wrap = %{changesets: [Worker.new(%{ref: 0}), Worker.new(%{ref: 1})]}

      [_job_1, _job_2] = Oban.insert_all(name, wrap)
    end

    test "handling empty changesets list from a wrapper", %{name: name} do
      assert [] = Oban.insert_all(name, %{changesets: []})
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
      changesets_1 = Enum.map(1..2, &Worker.new(%{ref: &1}))
      changesets_2 = Enum.map(3..4, &Worker.new(%{ref: &1}))
      changesets_3 = Enum.map(5..6, &Worker.new(%{ref: &1}))

      multi = Multi.new()
      multi = Oban.insert_all(name, multi, "jobs-1", changesets_1)
      multi = Oban.insert_all(name, multi, "jobs-2", changesets_2)
      multi = Multi.run(multi, "build-jobs-3", fn _, _ -> {:ok, changesets_3} end)
      multi = Oban.insert_all(name, multi, "jobs-3", & &1["build-jobs-3"])

      {:ok, %{"jobs-1" => jobs_1, "jobs-2" => jobs_2, "jobs-3" => jobs_3}} =
        Repo.transaction(multi)

      assert [%Job{}, %Job{}] = jobs_1
      assert [%Job{}, %Job{}] = jobs_2
      assert [%Job{}, %Job{}] = jobs_3
    end

    test "inserting multiple jobs from a changeset wrapper", %{name: name} do
      wrap = %{changesets: [Worker.new(%{ref: 0})]}

      multi = Multi.new()
      multi = Oban.insert_all(name, multi, "jobs-1", wrap)
      multi = Oban.insert_all(name, multi, "jobs-2", fn _ -> wrap end)

      {:ok, %{"jobs-1" => [_job_1], "jobs-2" => [_job_2]}} = Repo.transaction(multi)
    end

    test "handling empty changesets list from wrapper", %{name: name} do
      assert {:ok, %{jobs: []}} =
               name
               |> Oban.insert_all(Multi.new(), :jobs, %{changesets: []})
               |> Repo.transaction()
    end
  end

  describe "cancel_job/2" do
    test "cancelling an executing job by its id" do
      name = start_supervised_oban!(poll_interval: 10, queues: [alpha: 5])

      job = insert!(ref: 1, sleep: 100)

      assert_receive {:started, 1}

      Oban.cancel_job(name, job.id)

      refute_receive {:ok, 1}, 200

      assert %Job{state: "cancelled", cancelled_at: %_{}} = Repo.reload(job)

      assert %{running: []} = Oban.check_queue(name, queue: :alpha)
    end

    test "cancelling jobs that may or may not be executing" do
      name = start_supervised_oban!(poll_interval: 10, queues: [alpha: 5])

      job_a = insert!(%{ref: 1}, schedule_in: 10)
      job_b = insert!(%{ref: 2}, schedule_in: 10, state: "retryable")
      job_c = insert!(%{ref: 3}, state: "completed")
      job_d = insert!(%{ref: 4, sleep: 200})

      assert_receive {:started, 4}

      assert :ok = Oban.cancel_job(name, job_a.id)
      assert :ok = Oban.cancel_job(name, job_b.id)
      assert :ok = Oban.cancel_job(name, job_c.id)
      assert :ok = Oban.cancel_job(name, job_d.id)

      refute_receive {:ok, 4}, 250

      assert %Job{state: "cancelled", cancelled_at: %_{}} = Repo.reload(job_a)
      assert %Job{state: "cancelled", cancelled_at: %_{}} = Repo.reload(job_b)
      assert %Job{state: "completed", cancelled_at: nil} = Repo.reload(job_c)
      assert %Job{state: "cancelled", cancelled_at: %_{}} = Repo.reload(job_d)
    end
  end

  describe "cancel_all_jobs/2" do
    test "cancelling all jobs that may or may not be executing" do
      name = start_supervised_oban!(poll_interval: 10, queues: [alpha: 5])

      job_a = insert!(%{ref: 1}, schedule_in: 10)
      job_b = insert!(%{ref: 2}, schedule_in: 10, state: "retryable")
      job_c = insert!(%{ref: 3}, state: "completed")
      job_d = insert!(%{ref: 4, sleep: 200})

      assert_receive {:started, 4}

      assert {:ok, 3} = Oban.cancel_all_jobs(name, Job)

      refute_receive {:ok, 4}, 250

      assert %Job{state: "cancelled", cancelled_at: %_{}} = Repo.reload(job_a)
      assert %Job{state: "cancelled", cancelled_at: %_{}} = Repo.reload(job_b)
      assert %Job{state: "completed", cancelled_at: nil} = Repo.reload(job_c)
      assert %Job{state: "cancelled", cancelled_at: %_{}} = Repo.reload(job_d)
    end

    test "cancelling jobs with an alternate prefix" do
      name = start_supervised_oban!(prefix: "private", queues: [alpha: 5])

      insert!(name, %{ref: 1}, schedule_in: 10)
      insert!(name, %{ref: 2}, schedule_in: 10)

      assert {:ok, 2} = Oban.cancel_all_jobs(name, Job)
    end
  end

  describe "check_queue/2" do
    test "checking on queue state at runtime" do
      name =
        start_supervised_oban!(
          poll_interval: 5,
          queues: [alpha: 1, gamma: 2, delta: [limit: 2, paused: true]]
        )

      insert!([ref: 1, sleep: 500], queue: :alpha)
      insert!([ref: 2, sleep: 500], queue: :gamma)

      assert_receive {:started, 1}
      assert_receive {:started, 2}

      alpha_state = Oban.check_queue(name, queue: :alpha)

      assert %{limit: 1, node: _, paused: false} = alpha_state
      assert %{queue: "alpha", running: [_], started_at: %DateTime{}} = alpha_state

      assert %{limit: 2, queue: "gamma", running: [_]} = Oban.check_queue(name, queue: :gamma)
      assert %{paused: true, queue: "delta", running: []} = Oban.check_queue(name, queue: :delta)
    end

    test "checking an unknown or invalid queue" do
      name = start_supervised_oban!(testing: :manual)

      assert_raise ArgumentError, fn -> Oban.check_queue(name, wrong: nil) end
      assert_raise ArgumentError, fn -> Oban.check_queue(name, queue: nil) end
    end
  end

  describe "drain_queue/2" do
    setup :start_supervised_oban

    test "all jobs in a queue can be drained and executed synchronously", %{name: name} do
      insert!(ref: 1, action: "OK")
      insert!(ref: 2, action: "FAIL")
      insert!(ref: 3, action: "OK")
      insert!(ref: 4, action: "SNOOZE")
      insert!(ref: 5, action: "CANCEL")
      insert!(ref: 6, action: "DISCARD")
      insert!(%{ref: 7, action: "FAIL"}, max_attempts: 1)

      assert %{cancelled: 1, discard: 2, failure: 1, snoozed: 1, success: 2} ==
               Oban.drain_queue(name, queue: :alpha)

      assert_received {:ok, 1}
      assert_received {:fail, 2}
      assert_received {:ok, 3}
      assert_received {:cancel, 5}
    end

    test "all scheduled jobs are executed using :with_scheduled", %{name: name} do
      insert!(%{ref: 1, action: "OK"}, scheduled_at: seconds_from_now(3600))
      insert!(%{ref: 2, action: "OK"}, scheduled_at: seconds_from_now(7200))

      assert %{success: 0, failure: 0} = Oban.drain_queue(name, queue: :alpha)

      assert %{success: 2, failure: 0} =
               Oban.drain_queue(name, queue: :alpha, with_scheduled: true)
    end

    test "jobs scheduled up to a timestamp are executed", %{name: name} do
      insert!(%{ref: 1, action: "OK"}, scheduled_at: seconds_from_now(3600))
      insert!(%{ref: 2, action: "OK"}, scheduled_at: seconds_from_now(7200))

      assert %{success: 0, failure: 0} =
               Oban.drain_queue(name, queue: :alpha, with_scheduled: seconds_from_now(1))

      assert %{success: 1, failure: 0} =
               Oban.drain_queue(name, queue: :alpha, with_scheduled: seconds_from_now(3_600))

      assert %{success: 1, failure: 0} =
               Oban.drain_queue(name, queue: :alpha, with_scheduled: seconds_from_now(9_000))
    end

    test "job errors bubble up when :with_safety is false", %{name: name} do
      insert!(ref: 1, action: "FAIL")

      assert_raise RuntimeError, "FAILED", fn ->
        Oban.drain_queue(name, queue: :alpha, with_safety: false)
      end

      assert_received {:fail, 1}
    end

    test "job crashes bubble up when :with_safety is false", %{name: name} do
      insert!(ref: 1, action: "EXIT")

      assert_raise Oban.CrashError, fn ->
        Oban.drain_queue(name, queue: :alpha, with_safety: false)
      end

      assert_received {:exit, 1}
    end

    test "jobs inserted during perform are executed for :with_recursion", %{name: name} do
      insert!(ref: 1, recur: 3)

      assert %{success: 3} = Oban.drain_queue(name, queue: :alpha, with_recursion: true)

      assert_received {:ok, 1, 3}
      assert_received {:ok, 2, 3}
      assert_received {:ok, 3, 3}
    end

    test "only the specified number of jobs are executed for :with_limit", %{name: name} do
      insert!(ref: 1, action: "OK")
      insert!(ref: 2, action: "OK")

      assert %{success: 1} = Oban.drain_queue(name, queue: :alpha, with_limit: 1)

      assert_received {:ok, 1}
      refute_received {:ok, 2}
    end
  end

  describe "pause_queue/2 and resume_queue/2" do
    test "validating options" do
      name = start_supervised_oban!(testing: :manual)

      assert_invalid_opts(name, :pause_queue, queue: nil)
      assert_invalid_opts(name, :pause_queue, local_only: -1)
      assert_invalid_opts(name, :resume_queue, queue: nil)
      assert_invalid_opts(name, :resume_queue, local_only: -1)
    end

    test "pausing and resuming individual queues" do
      name = start_supervised_oban!(queues: [alpha: 5])

      assert :ok = Oban.pause_queue(name, queue: :alpha)

      with_backoff(fn ->
        assert %{paused: true} = Oban.check_queue(name, queue: :alpha)
      end)

      assert :ok = Oban.resume_queue(name, queue: :alpha)

      with_backoff(fn ->
        assert %{paused: false} = Oban.check_queue(name, queue: :alpha)
      end)
    end

    test "pausing queues only on the local node" do
      name1 = start_supervised_oban!(poll_interval: 10, queues: [alpha: 1])
      name2 = start_supervised_oban!(poll_interval: 10, queues: [alpha: 1])

      assert :ok = Oban.pause_queue(name2, queue: :alpha, local_only: true)

      with_backoff(fn ->
        assert %{paused: false} = Oban.check_queue(name1, queue: :alpha)
        assert %{paused: true} = Oban.check_queue(name2, queue: :alpha)
      end)
    end

    test "resuming queues only on the local node" do
      name1 = start_supervised_oban!(poll_interval: 10, queues: [alpha: 1])
      name2 = start_supervised_oban!(poll_interval: 10, queues: [alpha: 1])

      assert :ok = Oban.pause_queue(name1, queue: :alpha)

      with_backoff(fn ->
        assert %{paused: true} = Oban.check_queue(name1, queue: :alpha)
        assert %{paused: true} = Oban.check_queue(name2, queue: :alpha)
      end)

      assert :ok = Oban.resume_queue(name1, queue: :alpha, local_only: true)

      with_backoff(fn ->
        assert %{paused: false} = Oban.check_queue(name1, queue: :alpha)
        assert %{paused: true} = Oban.check_queue(name2, queue: :alpha)
      end)
    end

    test "trying to resume queues that don't exist" do
      name = start_supervised_oban!(testing: :manual)

      assert :ok = Oban.resume_queue(name, queue: :alpha)

      assert_raise ArgumentError, "queue :alpha does not exist locally", fn ->
        Oban.resume_queue(name, queue: :alpha, local_only: true)
      end
    end

    test "trying to pause queues that don't exist" do
      name = start_supervised_oban!(queues: [])

      assert :ok = Oban.pause_queue(name, queue: :alpha)

      assert_raise ArgumentError, "queue :alpha does not exist locally", fn ->
        Oban.pause_queue(name, queue: :alpha, local_only: true)
      end
    end
  end

  describe "retry_job/2" do
    setup :start_supervised_oban

    test "retrying jobs from multiple states", %{name: name} do
      job_a = insert!(%{ref: 1}, state: "discarded", max_attempts: 20, attempt: 20)
      job_b = insert!(%{ref: 2}, state: "completed", max_attempts: 20)
      job_c = insert!(%{ref: 3}, state: "available", max_attempts: 20)
      job_d = insert!(%{ref: 4}, state: "retryable", max_attempts: 20)
      job_e = insert!(%{ref: 5}, state: "executing", max_attempts: 1, attempt: 1)
      job_f = insert!(%{ref: 6}, state: "scheduled", max_attempts: 1, attempt: 1)

      assert :ok = Oban.retry_job(name, job_a.id)
      assert :ok = Oban.retry_job(name, job_b.id)
      assert :ok = Oban.retry_job(name, job_c.id)
      assert :ok = Oban.retry_job(name, job_d.id)
      assert :ok = Oban.retry_job(name, job_e.id)
      assert :ok = Oban.retry_job(name, job_f.id)

      assert %Job{state: "available", max_attempts: 21} = Repo.reload(job_a)
      assert %Job{state: "available", max_attempts: 20} = Repo.reload(job_b)
      assert %Job{state: "available", max_attempts: 20} = Repo.reload(job_c)
      assert %Job{state: "available", max_attempts: 20} = Repo.reload(job_d)
      assert %Job{state: "executing", max_attempts: 1} = Repo.reload(job_e)
      assert %Job{state: "scheduled", max_attempts: 1} = Repo.reload(job_f)
    end

    test "retrying all retryable jobs", %{name: name} do
      job_a = insert!(%{ref: 1}, state: "discarded", max_attempts: 20, attempt: 20)
      job_b = insert!(%{ref: 2}, state: "completed", max_attempts: 20)
      job_c = insert!(%{ref: 3}, state: "available", max_attempts: 20)
      job_d = insert!(%{ref: 4}, state: "retryable", max_attempts: 20)
      job_e = insert!(%{ref: 5}, state: "executing", max_attempts: 1, attempt: 1)
      job_f = insert!(%{ref: 6}, state: "scheduled", max_attempts: 1, attempt: 1)

      assert {:ok, 3} = Oban.retry_all_jobs(name, Job)

      assert %Job{state: "available", max_attempts: 21} = Repo.reload(job_a)
      assert %Job{state: "available", max_attempts: 20} = Repo.reload(job_b)
      assert %Job{state: "available", max_attempts: 20} = Repo.reload(job_c)
      assert %Job{state: "available", max_attempts: 20} = Repo.reload(job_d)
      assert %Job{state: "executing", max_attempts: 1} = Repo.reload(job_e)
      assert %Job{state: "scheduled", max_attempts: 1} = Repo.reload(job_f)
    end

    test "retrying jobs with an alternate prefix" do
      name = start_supervised_oban!(prefix: "private", queues: [alpha: 5])

      insert!(name, %{ref: 1}, state: "cancelled")
      insert!(name, %{ref: 2}, state: "cancelled")

      assert {:ok, 2} = Oban.retry_all_jobs(name, Job)
    end
  end

  describe "scale_queue/2" do
    test "validating options" do
      name = start_supervised_oban!(testing: :manual)

      assert_invalid_opts(name, :scale_queue, [])
      assert_invalid_opts(name, :scale_queue, queue: nil)
      assert_invalid_opts(name, :scale_queue, limit: -1)
      assert_invalid_opts(name, :scale_queue, local_only: -1)
    end

    test "scaling queues up" do
      name = start_supervised_oban!(queues: [alpha: 1])

      assert :ok = Oban.scale_queue(name, queue: :alpha, limit: 5)

      with_backoff(fn ->
        assert %{limit: 5} = Oban.check_queue(name, queue: :alpha)
      end)
    end

    test "forwarding scaling options for alternative engines" do
      # This is an abuse of `scale` because other engines support other options and passing
      # `paused` verifies that other options are supported.
      name = start_supervised_oban!(queues: [alpha: 1])

      assert :ok = Oban.scale_queue(name, queue: :alpha, limit: 5, paused: true)

      with_backoff(fn ->
        assert %{limit: 5, paused: true} = Oban.check_queue(name, queue: :alpha)
      end)
    end

    test "scaling queues only on the local node" do
      name1 = start_supervised_oban!(queues: [alpha: 2])
      name2 = start_supervised_oban!(queues: [alpha: 2])

      assert :ok = Oban.scale_queue(name2, queue: :alpha, limit: 1, local_only: true)

      with_backoff(fn ->
        assert %{limit: 2} = Oban.check_queue(name1, queue: :alpha)
        assert %{limit: 1} = Oban.check_queue(name2, queue: :alpha)
      end)
    end

    test "trying to scale queues that don't exist" do
      name = start_supervised_oban!(queues: [])

      assert :ok = Oban.scale_queue(name, queue: :alpha, limit: 1)

      assert_raise ArgumentError, "queue :alpha does not exist locally", fn ->
        Oban.scale_queue(name, queue: :alpha, limit: 1, local_only: true)
      end
    end
  end

  describe "start_queue/2" do
    test "validating options" do
      name = start_supervised_oban!(testing: :manual)

      assert_invalid_opts(name, :start_queue, [])
      assert_invalid_opts(name, :start_queue, queue: nil)
      assert_invalid_opts(name, :start_queue, limit: -1)
      assert_invalid_opts(name, :start_queue, local_only: -1)
      assert_invalid_opts(name, :start_queue, wat: -1)
    end

    test "starting individual queues dynamically" do
      name = start_supervised_oban!(queues: [alpha: 9])

      assert :ok = Oban.start_queue(name, queue: :gamma, limit: 5, refresh_interval: 10)
      assert :ok = Oban.start_queue(name, queue: :delta, limit: 6, paused: true)
      assert :ok = Oban.start_queue(name, queue: :alpha, limit: 5)

      with_backoff(fn ->
        assert supervised_queue?(name, "alpha")
        assert supervised_queue?(name, "delta")
        assert supervised_queue?(name, "gamma")
      end)
    end

    test "starting individual queues only on the local node" do
      name1 = start_supervised_oban!(queues: [])
      name2 = start_supervised_oban!(queues: [])

      assert :ok = Oban.start_queue(name1, queue: :alpha, limit: 1, local_only: true)

      with_backoff(fn ->
        assert supervised_queue?(name1, "alpha")
        refute supervised_queue?(name2, "alpha")
      end)
    end
  end

  describe "stop_queue/2" do
    test "validating options" do
      name = start_supervised_oban!(testing: :manual)

      assert_invalid_opts(name, :start_queue, queue: nil)
      assert_invalid_opts(name, :start_queue, local_only: -1)
    end

    test "stopping individual queues" do
      name = start_supervised_oban!(poll_interval: 10, queues: [alpha: 5, delta: 5, gamma: 5])

      assert supervised_queue?(name, "delta")
      assert supervised_queue?(name, "gamma")

      assert :ok = Oban.stop_queue(name, queue: :delta)
      assert :ok = Oban.stop_queue(name, queue: :gamma)

      with_backoff(fn ->
        assert supervised_queue?(name, "alpha")
        refute supervised_queue?(name, "delta")
        refute supervised_queue?(name, "gamma")
      end)
    end

    test "stopping individual queues only on the local node" do
      name1 = start_supervised_oban!(poll_interval: 10, queues: [alpha: 1])
      name2 = start_supervised_oban!(poll_interval: 10, queues: [alpha: 1])

      assert :ok = Oban.stop_queue(name2, queue: :alpha, local_only: true)

      with_backoff(fn ->
        assert supervised_queue?(name1, "alpha")
        refute supervised_queue?(name2, "alpha")
      end)
    end

    test "trying to stop queues that don't exist" do
      name = start_supervised_oban!(queues: [])

      assert :ok = Oban.pause_queue(name, queue: :alpha)

      assert_raise ArgumentError, "queue :alpha does not exist locally", fn ->
        Oban.pause_queue(name, queue: :alpha, local_only: true)
      end
    end
  end

  describe "whereis/1" do
    test "returning the Oban root process's pid" do
      name_1 = make_ref()
      name_2 = make_ref()

      {:ok, oban_1} = start_supervised({Oban, Keyword.put(@opts, :name, name_1)})
      {:ok, oban_2} = start_supervised({Oban, Keyword.put(@opts, :name, name_2)})

      refute oban_1 == oban_2
      assert Oban.whereis(name_1) == oban_1
      assert Oban.whereis(name_2) == oban_2
    end

    test "returning nil if root process not found" do
      refute Oban.whereis(make_ref())
    end
  end

  defp start_supervised_oban(context) do
    name =
      context
      |> Map.get(:oban_opts, [])
      |> Keyword.put_new(:testing, :manual)
      |> start_supervised_oban!()

    {:ok, name: name}
  end

  defp assert_invalid_opts(oban_name, function_name, opts) do
    assert_raise ArgumentError, fn -> apply(oban_name, function_name, [opts]) end
  end

  defp supervised_queue?(oban_name, queue_name) do
    oban_name
    |> Registry.whereis({:producer, queue_name})
    |> is_pid()
  end
end
