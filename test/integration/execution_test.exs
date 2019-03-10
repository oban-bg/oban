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
