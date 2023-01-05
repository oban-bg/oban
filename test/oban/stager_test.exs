defmodule Oban.StagerTest do
  use Oban.Case, async: true

  alias Oban.Stager
  alias Oban.TelemetryHandler

  describe "integration" do
    test "descheduling jobs to make them available for execution" do
      TelemetryHandler.attach_events()

      then = DateTime.add(DateTime.utc_now(), -30)

      job_1 = insert!([ref: 1, action: "OK"], inserted_at: then, schedule_in: -9)
      job_2 = insert!([ref: 2, action: "OK"], inserted_at: then, schedule_in: -5)
      job_3 = insert!([ref: 3, action: "OK"], inserted_at: then, schedule_in: 10)

      start_supervised_oban!(stage_interval: 5, testing: :disabled)

      with_backoff(fn ->
        assert %{state: "available"} = Repo.reload(job_1)
        assert %{state: "available"} = Repo.reload(job_2)
        assert %{state: "scheduled"} = Repo.reload(job_3)
      end)

      assert_receive {:event, :start, %{system_time: _}, %{conf: _, plugin: Stager}}
      assert_receive {:event, :stop, %{duration: _}, %{plugin: Stager} = meta}

      assert %{staged_count: 2, staged_jobs: [%{state: "scheduled"} | _]} = meta
    end

    @tag :capture_log
    test "switching to local mode without functional pubsub" do
      name =
        start_supervised_oban!(
          stage_interval: 2,
          notifier: Oban.Notifiers.Postgres,
          testing: :disabled
        )

      {:via, _, {_, prod_name}} = Oban.Registry.via(name, {:producer, "staging_test"})

      Registry.register(Oban.Registry, prod_name, nil)

      assert_receive {:notification, :insert, %{"queue" => "staging_test"}}
    end
  end
end
