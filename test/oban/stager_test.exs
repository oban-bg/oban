defmodule Oban.StagerTest do
  use Oban.Case, async: true

  alias Oban.Stager
  alias Oban.TelemetryHandler

  describe "integration" do
    test "descheduling jobs to make them available for execution" do
      TelemetryHandler.attach_events()

      job_1 = insert!(%{}, state: "scheduled", scheduled_at: seconds_ago(1))
      job_2 = insert!(%{}, state: "scheduled", scheduled_at: seconds_from_now(1))
      job_3 = insert!(%{}, state: "retryable")

      start_supervised_oban!(stage_interval: 5, testing: :disabled)

      with_backoff(fn ->
        assert %{state: "available"} = Repo.reload(job_1)
        assert %{state: "scheduled"} = Repo.reload(job_2)
        assert %{state: "available"} = Repo.reload(job_3)
      end)

      assert_receive {:event, :start, %{system_time: _}, %{conf: _, plugin: Stager}}
      assert_receive {:event, :stop, %{duration: _}, %{plugin: Stager} = meta}

      assert %{staged_count: 2, staged_jobs: jobs} = meta

      assert ~w(retryable scheduled) =
               jobs
               |> Enum.map(& &1.state)
               |> Enum.sort()
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
