defmodule Oban.Integration.ExecutingTest do
  use Oban.Case

  alias Oban.Query

  @moduletag :integration

  @oban_opts repo: Repo, queues: [alpha: 3, beta: 3, gamma: 3, delta: 3], poll_interval: 20

  setup do
    start_supervised!({Oban, @oban_opts})

    :ok
  end

  property "jobs in running queues are executed" do
    check all jobs <- list_of(job()), max_runs: 20 do
      jobs = Enum.map(jobs, &Oban.insert!/1)

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
    end
  end

  test "advisory locks are released after jobs have executed" do
    # Test order is random and most tests don't release their locks.
    initial_count = advisory_lock_count()

    insert_job!(ref: 1, action: "OK")
    insert_job!(ref: 2, action: "OK")
    insert_job!(ref: 3, action: "OK")

    assert_receive {:ok, 1}
    assert_receive {:ok, 2}
    assert_receive {:ok, 3}

    with_backoff(fn ->
      assert advisory_lock_count() == initial_count
    end)
  end

  defp job do
    gen all queue <- member_of(~w(alpha beta gamma delta)),
            action <- member_of(~w(OK FAIL ERROR EXIT)),
            ref <- integer(),
            max_attempts <- integer(1..20) do
      args = %{ref: ref, action: action}
      opts = [queue: queue, max_attempts: max_attempts]

      Worker.new(args, opts)
    end
  end

  # The `maximum_attempts` option is set to 1 to prevent retries. This ensures that the state for
  # failed jobs will be `discarded`.
  defp action_to_state("OK", _max), do: "completed"
  defp action_to_state(_state, 1), do: "discarded"
  defp action_to_state(_state, max) when max > 1, do: "retryable"

  defp insert_job!(args) do
    args
    |> Worker.new(queue: :alpha)
    |> Oban.insert!()
  end

  @advisory_query """
  SELECT count(*) FROM pg_locks WHERE locktype = 'advisory' AND classid = #{Query.to_ns()}
  """
  defp advisory_lock_count do
    {:ok, %{rows: [[count]]}} = Repo.query(@advisory_query)

    count
  end
end
