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
    def perform(%{args: %{"index" => index, "status" => status, "bin_pid" => bin_pid}}) do
      pid = bin_to_pid(bin_pid)

      case status do
        "OK" ->
          send(pid, {:ok, index})

        "FAIL" ->
          send(pid, {:error, index})

          raise RuntimeError, "FAILED"
      end
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

    for index <- 1..5, status <- ~w(OK FAIL), queue <- @queues do
      %{index: index, status: status, bin_pid: Worker.pid_to_bin()}
      |> Worker.new(queue: queue)
      |> Repo.insert!()

      assert_receive {_, index}
    end

    Process.sleep(10)

    query = from(job in Job, group_by: job.state, select: {job.state, count()})

    assert Repo.all(query) == [{"available", 20}, {"completed", 20}]

    :ok = stop_supervised(Supervisor)
  end

  # test telemetry integration
  # test scheduled jobs
  # test retries
  # test expired job rescue
end
