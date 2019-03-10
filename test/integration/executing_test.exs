defmodule Oban.Integration.ExecutingTest do
  use Oban.Case
  use PropCheck

  alias Ecto.Adapters.SQL.Sandbox

  @oban_opts poll_interval: 10,
             repo: Repo,
             queues: [alpha: 3, beta: 3, gamma: 3, delta: 3]

  defmodule Worker do
    use Oban.Worker

    @impl Worker
    def perform(%{"ref" => ref, "action" => action, "bin_pid" => bin_pid}) do
      pid = bin_to_pid(bin_pid)

      case action do
        "OK" ->
          send(pid, {:ok, ref})

        "FAIL" ->
          send(pid, {:fail, ref})

          raise RuntimeError, "FAILED"

        "EXIT" ->
          send(pid, {:exit, ref})

          GenServer.call(FakeServer, :exit)
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

  def setup do
    Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})

    start_supervised!({Oban, @oban_opts})

    fn -> stop_supervised(Oban) end
  end

  property "jobs in running queues are executed", [:verbose] do
    property_setup(
      &setup/0,
      forall jobs <- jobs() do
        # Enqueue all the jobs at once before asserting on the messages, this allows the jobs to be
        # executed in batches.
        jobs = Enum.map(jobs, &Repo.insert!/1)

        for job <- jobs do
          %{args: %{ref: ref, action: action}, id: id, max_attempts: max} = job

          assert_receive {_, ^ref}

          with_backoff(fn ->
            job = Repo.get(Job, id)

            assert job.attempt == 1
            assert job.attempted_at
            assert job.state == action_to_state(action, max)
          end)
        end

        true
      end
    )
  end

  # Generators

  def jobs do
    let list <- list({queue(), integer(), action(), max_attempts()}) do
      for {queue, ref, action, max_attempts} <- list do
        args = %{ref: ref, bin_pid: Worker.pid_to_bin(), action: action}
        opts = [queue: queue, max_attempts: max_attempts]

        Worker.new(args, opts)
      end
    end
  end

  def max_attempts do
    range(1, 25)
  end

  def queue do
    oneof(~w(alpha beta gamma delta))
  end

  def action do
    oneof(~w(OK FAIL EXIT))
  end

  # Helpers

  # The `maximum_attempts` option is set to 1 to prevent retries. This ensures that the state for
  # failed jobs will be `discarded`.
  defp action_to_state("OK", _max), do: "completed"
  defp action_to_state(_state, 1), do: "discarded"
  defp action_to_state(_state, max) when max > 1, do: "available"
end
