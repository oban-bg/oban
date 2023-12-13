defmodule ObanTest do
  use Oban.Case, async: true

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

    test "name must be unique" do
      name = make_ref()
      opts = Keyword.put(@opts, :name, name)

      {:ok, pid} = Oban.start_link(opts)
      {:error, {:already_started, ^pid}} = Oban.start_link(opts)
    end
  end

  describe "stop/1" do
    test "slow jobs are allowed to complete within the shutdown grace period" do
      %Job{id: id_1} = insert!(ref: 1, sleep: 5)
      %Job{id: id_2} = insert!(ref: 2, sleep: 5000)

      name =
        start_supervised_oban!(
          queues: [alpha: 1],
          shutdown_grace_period: 50,
          stage_interval: 10
        )

      assert_receive {:started, 1}
      assert_receive {:started, 2}

      :ok = stop_supervised(name)

      assert_receive {:ok, 1}
      refute_receive {:ok, 2}

      assert Repo.get(Job, id_1).state == "completed"
      assert Repo.get(Job, id_2).state == "executing"
    end

    test "additional jobs aren't started after shutdown starts" do
      insert!(ref: 1, sleep: 50)

      name =
        start_supervised_oban!(
          queues: [alpha: 1],
          shutdown_grace_period: 40,
          stage_interval: 10
        )

      assert_receive {:started, 1}

      :ok = stop_supervised(name)

      insert!(ref: 2, sleep: 50)

      refute_receive {:started, 2}
    end

    test "queue shutdown grace period applies comprehensively to all queues" do
      insert!([ref: 1, sleep: 500], queue: :alpha)
      insert!([ref: 2, sleep: 500], queue: :alpha)
      insert!([ref: 3, sleep: 500], queue: :omega)
      insert!([ref: 3, sleep: 500], queue: :omega)

      name =
        start_supervised_oban!(
          queues: [alpha: 1, omega: 1],
          shutdown_grace_period: 50,
          stage_interval: 10
        )

      assert_receive {:started, 1}
      assert_receive {:started, 3}

      {time, _} = :timer.tc(fn -> stop_supervised(name) end)

      assert System.convert_time_unit(time, :microsecond, :millisecond) >= 50

      refute_receive {:started, 2}
      refute_receive {:started, 4}
    end
  end

  describe "check_queue/2" do
    test "checking on queue state at runtime" do
      name =
        start_supervised_oban!(
          queues: [alpha: 1, gamma: 2, delta: [limit: 2, paused: true]],
          stage_interval: 5
        )

      insert!([ref: 1, sleep: 500], queue: :alpha)
      insert!([ref: 2, sleep: 500], queue: :gamma)

      assert_receive {:started, 1}
      assert_receive {:started, 2}

      alpha_state = Oban.check_queue(name, queue: :alpha)

      assert %{limit: 1, node: _, paused: false, uuid: _} = alpha_state
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
      name1 = start_supervised_oban!(stage_interval: 10, queues: [alpha: 1])
      name2 = start_supervised_oban!(stage_interval: 10, queues: [alpha: 1])

      assert :ok = Oban.pause_queue(name2, queue: :alpha, local_only: true)

      with_backoff(fn ->
        assert %{paused: false} = Oban.check_queue(name1, queue: :alpha)
        assert %{paused: true} = Oban.check_queue(name2, queue: :alpha)
      end)
    end

    test "pausing queues on a specific node" do
      name = start_supervised_oban!(node: "web.1", stage_interval: 10, queues: [alpha: 1])

      assert :ok = Oban.pause_queue(name, queue: :alpha, node: "web.2")

      with_backoff(fn ->
        assert %{paused: false} = Oban.check_queue(name, queue: :alpha)
      end)

      assert :ok = Oban.pause_queue(name, queue: :alpha, node: "web.1")

      with_backoff(fn ->
        assert %{paused: true} = Oban.check_queue(name, queue: :alpha)
      end)
    end

    test "resuming queues only on the local node" do
      opts = [notifier: Oban.Notifiers.PG, stage_interval: 10, queues: [alpha: 1]]

      name1 = start_supervised_oban!(opts)
      name2 = start_supervised_oban!(opts)

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

    test "resuming queues on a specific node" do
      name = start_supervised_oban!(node: "web.1", stage_interval: 10, queues: [alpha: 1])

      Oban.pause_queue(name, queue: :alpha)

      with_backoff(fn ->
        assert %{paused: true} = Oban.check_queue(name, queue: :alpha)
      end)

      Oban.resume_queue(name, queue: :alpha, node: "web.2")

      with_backoff(fn ->
        assert %{paused: true} = Oban.check_queue(name, queue: :alpha)
      end)

      Oban.resume_queue(name, queue: :alpha, node: "web.1")

      with_backoff(fn ->
        assert %{paused: false} = Oban.check_queue(name, queue: :alpha)
      end)
    end

    test "trying to pause queues that don't exist" do
      name = start_supervised_oban!(queues: [])

      assert :ok = Oban.pause_queue(name, queue: :alpha)

      assert_raise ArgumentError, "queue :alpha does not exist locally", fn ->
        Oban.pause_queue(name, queue: :alpha, local_only: true)
      end
    end

    test "trying to resume queues that don't exist" do
      name = start_supervised_oban!(testing: :manual)

      assert :ok = Oban.resume_queue(name, queue: :alpha)

      assert_raise ArgumentError, "queue :alpha does not exist locally", fn ->
        Oban.resume_queue(name, queue: :alpha, local_only: true)
      end
    end
  end

  describe "pause_all_queues/2 and resume_all_queues/2" do
    test "pausing and resuming all queues" do
      name = start_supervised_oban!(queues: [alpha: 1, gamma: 1, delta: 1])

      assert :ok = Oban.pause_all_queues(name)

      with_backoff(fn ->
        assert %{paused: true} = Oban.check_queue(name, queue: :alpha)
        assert %{paused: true} = Oban.check_queue(name, queue: :gamma)
        assert %{paused: true} = Oban.check_queue(name, queue: :delta)
      end)

      assert :ok = Oban.resume_all_queues(name)

      with_backoff(fn ->
        assert %{paused: false} = Oban.check_queue(name, queue: :alpha)
        assert %{paused: false} = Oban.check_queue(name, queue: :gamma)
        assert %{paused: false} = Oban.check_queue(name, queue: :delta)
      end)
    end

    test "pausing and resuming all local queues" do
      opts = [queues: [alpha: 1, gamma: 1]]

      name1 = start_supervised_oban!(opts)
      name2 = start_supervised_oban!(opts)

      assert :ok = Oban.pause_all_queues(name1, local_only: true)

      with_backoff(fn ->
        assert %{paused: true} = Oban.check_queue(name1, queue: :alpha)
        assert %{paused: true} = Oban.check_queue(name1, queue: :gamma)

        assert %{paused: false} = Oban.check_queue(name2, queue: :alpha)
        assert %{paused: false} = Oban.check_queue(name2, queue: :gamma)
      end)

      assert :ok = Oban.pause_all_queues(name2, local_only: true)
      assert :ok = Oban.resume_all_queues(name1, local_only: true)

      with_backoff(fn ->
        assert %{paused: false} = Oban.check_queue(name1, queue: :alpha)
        assert %{paused: false} = Oban.check_queue(name1, queue: :gamma)

        assert %{paused: true} = Oban.check_queue(name2, queue: :alpha)
        assert %{paused: true} = Oban.check_queue(name2, queue: :gamma)
      end)
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
      name = start_supervised_oban!(stage_interval: 10, queues: [alpha: 5, delta: 5, gamma: 5])

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
      name1 = start_supervised_oban!(stage_interval: 10, queues: [alpha: 1])
      name2 = start_supervised_oban!(stage_interval: 10, queues: [alpha: 1])

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

  test "config/0 of a facade instance" do
    defmodule MyOban do
      use Oban, otp_app: :oban, repo: Oban.Test.Repo
    end

    start_supervised!({MyOban, testing: :inline})

    assert %{name: MyOban, repo: Oban.Test.Repo} = MyOban.config()
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
