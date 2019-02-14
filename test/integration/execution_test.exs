defmodule Oban.Integration.ExecutionTest do
  use Oban.Case

  import Ecto.Query

  @queues ~w(alpha beta gamma delta)a

  defmodule Supervisor do
    use Oban,
      repo: Oban.Test.Repo,
      queues: [alpha: 5, beta: 5, gamma: 5, delta: 5]
  end

  defmodule Worker do
    use Oban.Worker

    @impl Worker
    def perform(%{args: %{"id" => id, "status" => status, "bin_pid" => bin_pid}}) do
      pid = bin_to_pid(bin_pid)

      case status do
        "OK" ->
          send(pid, {:ok, id})

        "FAIL" ->
          send(pid, {:error, id})

          raise RuntimeError, "FAILED"
      end
    end

    def perform(%{args: %{"id" => id, "sleep" => sleep, "bin_pid" => bin_pid}}) do
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
    {:ok, _} = start_supervised({Supervisor, poll_interval: 10})

    for id <- 1..5, status <- ~w(OK FAIL), queue <- @queues do
      insert_job!(%{id: id, status: status}, queue: queue)

      assert_receive {_, id}
    end

    with_backoff(fn ->
      query = from(job in Job, select: count())

      available_query = where(query, state: "available", attempt: 1)
      completed_query = where(query, state: "completed", attempt: 1)

      assert Repo.one(available_query) == 20
      assert Repo.one(completed_query) == 20
    end)

    :ok = stop_supervised(Supervisor)
  end

  test "jobs can be scheduled for future execution" do
    for seconds <- 1..5, do: insert_job!(%{}, scheduled_in: seconds)

    query =
      Job
      |> where([job], job.scheduled_at > ^NaiveDateTime.utc_now())
      |> select([job], count(job.id))

    assert Repo.one(query) == 5
  end

  test "jobs that have reached their maximum attempts are marked as discarded" do
    {:ok, _} = start_supervised({Supervisor, poll_interval: 10})

    %Job{id: id} = insert_job!(%{id: 0, status: "FAIL"}, max_attempts: 1)

    assert_receive {:error, 0}

    with_backoff(fn -> assert Repo.get(Job, id).state == "discarded" end)

    :ok = stop_supervised(Supervisor)
  end

  test "slow jobs are allowed to complete within the shutdown grace period" do
    _pd = start_supervised!({Supervisor, poll_interval: 10, shutdown_grace_period: 500})

    %Job{id: id_1} = insert_job!(%{id: 1, sleep: 200})
    %Job{id: id_2} = insert_job!(%{id: 2, sleep: 4000})

    :ok = stop_supervised(Supervisor)

    assert_receive {:ok, 1}
    refute_receive {:ok, 2}

    assert Repo.get(Job, id_1).state == "completed"
    assert Repo.get(Job, id_2).state == "executing"
  end

  defp insert_job!(args, opts \\ []) do
    opts = Keyword.put_new(opts, :queue, "alpha")

    args
    |> Map.put(:bin_pid, Worker.pid_to_bin())
    |> Worker.new(opts)
    |> Repo.insert!()
  end
end
