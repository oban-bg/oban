defmodule Oban.Integration.ExecutingTest do
  use Oban.Case

  import ExUnit.CaptureLog

  alias Oban.Plugins.Stager

  @moduletag :integration

  describe "properties" do
    setup do
      name = start_supervised_oban!(queues: [alpha: 3, beta: 3, gamma: 3, delta: 3])

      {:ok, name: name}
    end

    property "jobs inserted into running queues are executed", context do
      check all jobs <- list_of(job()), max_runs: 20 do
        capture_log(fn ->
          for job <- Oban.insert_all(context.name, jobs) do
            %{args: %{"ref" => ref, "action" => action}, id: id, max_attempts: max} = job

            assert_receive {_, ^ref}

            with_backoff(fn ->
              job = Repo.get(Job, id)

              assert job.attempt == 1
              assert job.attempted_at
              assert job.state == action_to_state(action, max)

              case job.state do
                "completed" ->
                  assert job.completed_at

                "discarded" ->
                  refute job.completed_at
                  assert job.discarded_at
                  assert [%{"attempt" => _, "at" => _, "error" => _} | _] = job.errors

                "retryable" ->
                  refute job.completed_at
                  assert DateTime.compare(job.scheduled_at, DateTime.utc_now()) == :gt
                  assert length(job.errors) > 0
                  assert [%{"attempt" => 1, "at" => _, "error" => _} | _] = job.errors

                "scheduled" ->
                  refute job.completed_at
                  assert DateTime.compare(job.scheduled_at, DateTime.utc_now()) == :gt
                  assert job.max_attempts > 1
              end
            end)
          end
        end)
      end
    end
  end

  test "jobs transitioned to available for running queues are executed" do
    name = start_supervised_oban!(plugins: [{Stager, interval: 25}], queues: [alpha: 3])

    job_1 = insert!(%{ref: 1, action: "OK"}, queue: "alpha", state: "completed")
    job_2 = insert!(%{ref: 2, action: "OK"}, queue: "alpha", state: "discarded")

    Oban.retry_job(name, job_1.id)
    Oban.retry_job(name, job_2.id)

    assert_receive {:ok, 1}
    assert_receive {:ok, 2}
  end

  defp job do
    gen all queue <- member_of(~w(alpha beta gamma delta)),
            action <- member_of(~w(OK DISCARD ERROR EXIT FAIL KILL SNOOZE TASK_ERROR)),
            ref <- integer(),
            max_attempts <- integer(1..20),
            priority <- integer(0..3),
            meta <- map_of(string(:ascii), integer()),
            tags <- list_of(string(:ascii)) do
      args = %{ref: ref, action: action}

      opts = [
        queue: queue,
        max_attempts: max_attempts,
        priority: priority,
        meta: meta,
        tags: tags
      ]

      build(args, opts)
    end
  end

  defp action_to_state("DISCARD", _), do: "discarded"
  defp action_to_state("OK", _max), do: "completed"
  defp action_to_state("SNOOZE", _), do: "scheduled"
  defp action_to_state(_state, 1), do: "discarded"
  defp action_to_state(_state, max) when max > 1, do: "retryable"
end
