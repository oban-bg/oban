defmodule Oban.Integration.ExecutionTest do
  use Oban.Case

  import Ecto.Query

  @oban_opts poll_interval: 10,
             repo: Oban.Test.Repo,
             queues: [alpha: 3, beta: 3, gamma: 3, delta: 3]

  defmodule Worker do
    use Oban.Worker

    @impl Worker
    def perform(%{"id" => id, "status" => status, "bin_pid" => bin_pid}) do
      pid = bin_to_pid(bin_pid)

      case status do
        "OK" ->
          send(pid, {:ok, id})

        "FAIL" ->
          send(pid, {:error, id})

          raise RuntimeError, "FAILED"
      end
    end

    def perform(%{"id" => id, "sleep" => sleep, "bin_pid" => bin_pid}) do
      :ok = Process.sleep(sleep)

      bin_pid
      |> bin_to_pid()
      |> send({:ok, id})
    end

    def pid_to_bin(pid \\ self()) do
      pid
      |> :erlang.term_to_binary()
      |> Base.encode64()
    end

    def bin_to_pid(bin) do
      bin
      |> Base.decode64!()
      |> :erlang.binary_to_term()
    end
  end

  test "jobs enqueued in configured queues are executed" do
    start_supervised!({Oban, @oban_opts})

    for id <- 1..5, status <- ~w(OK FAIL), queue <- ~w(alpha beta gamma delta) do
      insert_job!([id: id, status: status], queue: queue)

      assert_receive {_, id}
    end

    with_backoff(fn ->
      query = from(job in Job, select: count())

      available_query = where(query, state: "available", attempt: 1)
      completed_query = where(query, state: "completed", attempt: 1)

      assert Repo.one(available_query) == 20
      assert Repo.one(completed_query) == 20
    end)

    :ok = stop_supervised(Oban)
  end

  test "jobs can be scheduled for future execution" do
    for seconds <- 1..5, do: insert_job!([], scheduled_in: seconds)

    query =
      Job
      |> where([job], job.scheduled_at > ^NaiveDateTime.utc_now())
      |> select([job], count(job.id))

    assert Repo.one(query) == 5
  end

  test "jobs that have reached their maximum attempts are marked as discarded" do
    start_supervised!({Oban, @oban_opts})

    %Job{id: id} = insert_job!([id: 0, status: "FAIL"], max_attempts: 1)

    assert_receive {:error, 0}

    with_backoff(fn -> assert Repo.get(Job, id).state == "discarded" end)

    :ok = stop_supervised(Oban)
  end

  test "slow jobs are allowed to complete within the shutdown grace period" do
    start_supervised!({Oban, Keyword.put(@oban_opts, :shutdown_grace_period, 500)})

    %Job{id: id_1} = insert_job!(id: 1, sleep: 50)
    %Job{id: id_2} = insert_job!(id: 2, sleep: 4000)

    assert_receive {:ok, 1}

    :ok = stop_supervised(Oban)

    assert Repo.get(Job, id_1).state == "completed"
    assert Repo.get(Job, id_2).state == "executing"
  end

  # Orphaned jobs were started but never managed to finish. This is likely
  # because the job couldn't complete within the shutdown grace period.
  # Regardless, we want to start the job again and give it another chance to
  # finish.
  test "orphaned jobs are transitioned back to an available state" do
    start_supervised({Oban, Keyword.put(@oban_opts, :shutdown_grace_period, 50)})

    insert_job!(id: 1, sleep: 1)
    insert_job!(id: 2, sleep: 100)

    # By confirming that the first job completed we can be sure that the second
    # job had time to start.
    assert_receive {:ok, 1}
    refute_receive {:ok, 2}, 50

    :ok = stop_supervised(Oban)

    unlock_all()

    start_supervised({Oban, @oban_opts})

    assert_receive {:ok, 2}, 200
    refute_receive {:ok, 1}

    :ok = stop_supervised(Oban)
  end

  test "telemetry events are emitted for executed jobs" do
    defmodule Handler do
      def handle([:oban, :job, :executed], timing, meta, pid) do
        send(pid, {:executed, meta[:event], timing})
      end
    end

    :telemetry.attach("job-handler", [:oban, :job, :executed], &Handler.handle/4, self())

    {:ok, _} = start_supervised({Oban, @oban_opts})

    insert_job!(%{id: 1, status: "OK"})
    insert_job!(%{id: 2, status: "FAIL"})

    assert_receive {:executed, :success, success_timing}
    assert_receive {:executed, :failure, failure_timing}

    assert success_timing > 0
    assert failure_timing > 0

    :ok = stop_supervised(Oban)
  end

  defp insert_job!(args, opts \\ []) do
    opts = Keyword.put_new(opts, :queue, "alpha")

    args
    |> Map.new()
    |> Map.put(:bin_pid, Worker.pid_to_bin())
    |> Worker.new(opts)
    |> Repo.insert!()
  end

  defp unlock_all do
    Repo.query("SELECT pg_advisory_unlock_all()")
  end
end
