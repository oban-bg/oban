defmodule Oban.Integration.ExecutingTest do
  use Oban.Case

  import ExUnit.CaptureLog

  @moduletag :integration

  @oban_opts repo: Repo, queues: [alpha: 3, beta: 3, gamma: 3, delta: 3]

  setup do
    start_supervised!({Oban, @oban_opts})

    :ok
  end

  property "individual jobs inserted into running queues are executed" do
    check all jobs <- list_of(job()), max_runs: 20 do
      capture_log(fn ->
        jobs = Enum.map(jobs, &Oban.insert!/1)

        for job <- jobs do
          %{args: %{ref: ref, action: action}, id: id, max_attempts: max} = job

          assert_receive {_, ^ref}

          with_backoff(fn ->
            job = Repo.get(Job, id)

            assert job.attempt == 1
            assert job.attempted_at
            assert job.state == action_to_state(action, max)

            case job.state do
              "completed" ->
                assert job.completed_at

              "scheduled" ->
                refute job.completed_at
                assert job.scheduled_at > NaiveDateTime.utc_now()
                assert job.max_attempts > 1

              _ ->
                assert job.completed_at
                assert length(job.errors) > 0
                assert [%{"attempt" => 1, "at" => _, "error" => _} | _] = job.errors
            end
          end)
        end
      end)
    end
  end

  defp job do
    gen all queue <- member_of(~w(alpha beta gamma delta)),
            action <- member_of(~w(OK ERROR EXIT FAIL SNOOZE TASK_ERROR)),
            ref <- integer(),
            max_attempts <- integer(1..20),
            priority <- integer(0..3),
            tags <- list_of(string(:ascii)) do
      args = %{ref: ref, action: action}
      opts = [queue: queue, max_attempts: max_attempts, priority: priority, tags: tags]

      Worker.new(args, opts)
    end
  end

  defp action_to_state("OK", _max), do: "completed"
  defp action_to_state("SNOOZE", _), do: "scheduled"
  defp action_to_state(_state, 1), do: "discarded"
  defp action_to_state(_state, max) when max > 1, do: "retryable"
end
