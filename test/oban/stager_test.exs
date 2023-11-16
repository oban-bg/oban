defmodule Oban.StagerTest do
  use Oban.Case, async: true

  alias Oban.Stager
  alias Oban.TelemetryHandler

  describe "integration" do
    test "executing jobs from an insert notification" do
      name =
        start_supervised_oban!(
          queues: [alpha: 1, gamma: 1],
          stage_interval: 10_000,
          testing: :disabled
        )

      Oban.insert(name, Worker.new(%{action: "OK", ref: 0}, queue: :alpha))
      Oban.insert_all(name, [Worker.new(%{action: "OK", ref: 1}, queue: :gamma)])

      assert_receive {:ok, 0}
      assert_receive {:ok, 1}
    end

    test "descheduling jobs to make them available for execution" do
      job_1 = insert!(%{}, state: "scheduled", scheduled_at: seconds_ago(10))
      job_2 = insert!(%{}, state: "scheduled", scheduled_at: seconds_from_now(10))
      job_3 = insert!(%{}, state: "retryable")

      start_supervised_oban!(stage_interval: 5, testing: :disabled)

      with_backoff(fn ->
        assert %{state: "available"} = Repo.reload(job_1)
        assert %{state: "scheduled"} = Repo.reload(job_2)
        assert %{state: "available"} = Repo.reload(job_3)
      end)
    end

    test "emitting telemetry data for staged jobs" do
      TelemetryHandler.attach_events()

      start_supervised_oban!(stage_interval: 5, testing: :disabled)

      assert_receive {:event, :stop, %{duration: _}, %{plugin: Stager} = meta}

      assert %{staged_count: _, staged_jobs: []} = meta
    end

    test "switching to local mode without functional pubsub" do
      ref = :telemetry_test.attach_event_handlers(self(), [[:oban, :stager, :switch]])

      name =
        start_supervised_oban!(
          stage_interval: 2,
          notifier: Oban.Notifiers.Postgres,
          testing: :disabled
        )

      {:via, _, {_, prod_name}} = Oban.Registry.via(name, {:producer, "staging_test"})

      Registry.register(Oban.Registry, prod_name, nil)

      assert_receive {:notification, :insert, %{"queue" => "staging_test"}}

      assert_receive {[:oban, :stager, :switch], ^ref, %{}, %{mode: :local}}
    end
  end
end
