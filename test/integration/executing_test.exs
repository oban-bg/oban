defmodule Oban.Integration.ExecutingTest do
  use Oban.Case
  use PropCheck

  @moduletag :integration

  @oban_opts repo: Repo, queues: [alpha: 3, beta: 3, gamma: 3, delta: 3]

  def setup do
    start_supervised!({Oban, @oban_opts})

    fn -> stop_supervised(Oban) end
  end

  property "jobs in running queues are executed" do
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
            assert job.completed_at
            assert job.state == action_to_state(action, max)

            if job.state != "completed" do
              assert length(job.errors) > 0
              assert [%{"attempt" => 1, "at" => _, "error" => _} | _] = job.errors
            end
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
    oneof(~w(OK FAIL ERROR EXIT))
  end

  # Helpers

  # The `maximum_attempts` option is set to 1 to prevent retries. This ensures that the state for
  # failed jobs will be `discarded`.
  defp action_to_state("OK", _max), do: "completed"
  defp action_to_state(_state, 1), do: "discarded"
  defp action_to_state(_state, max) when max > 1, do: "retryable"
end
