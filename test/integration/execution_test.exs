defmodule Oban.Integration.ExecutionTest do
  use Oban.Case, async: true

  @queues ~w(alpha beta gamma delta)a

  defmodule Supervisor do
    use Oban,
      repo: Oban.Test.Repo,
      queues: [alpha: 5, beta: 5, gamma: 5, delta: 5]
  end

  defmodule Worker do
    use Oban.Worker

    @impl Worker
    def perform(%{params: [index, "OK", bin_pid]}) do
      bin_pid
      |> bin_to_pid()
      |> send({:ok, index})
    end

    def perform(%{params: [_index, "FAIL", _bin_pid]}) do
      raise RuntimeError, "FAILED!"
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
    {:ok, _} = start_supervised(Supervisor)

    for index <- 1..10, status <- ~w(OK FAIL), queue <- @queues do
      %{index: index, status: status, bin_pid: Worker.pid_to_bin()}
      |> Worker.new(queue: queue)
      |> Repo.insert!()

      if status == "OK", do: assert_receive {:ok, index}
    end

    # check the database table:
    #   all jobs should be in there, we should have N available and N completed

    :ok = stop_supervised(Supervisor)
  end

  # telemetry integration
  # retries
  # rescue jobs that have timed out
end
