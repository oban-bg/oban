defmodule Oban.Plugins.StagerTest do
  use Oban.Case

  alias Oban.Plugins.Stager
  alias Oban.TelemetryHandler

  describe "validate/1" do
    test "validating numerical values" do
      assert {:error, _} = Stager.validate(interval: nil)
      assert {:error, _} = Stager.validate(interval: 0)

      assert :ok = Stager.validate(interval: 1)
      assert :ok = Stager.validate(interval: :timer.seconds(30))
    end
  end

  describe "integration" do
    test "descheduling jobs to make them available for execution" do
      TelemetryHandler.attach_events()

      then = DateTime.add(DateTime.utc_now(), -30)

      job_1 = insert!([ref: 1, action: "OK"], inserted_at: then, schedule_in: -9)
      job_2 = insert!([ref: 2, action: "OK"], inserted_at: then, schedule_in: -5)
      job_3 = insert!([ref: 3, action: "OK"], inserted_at: then, schedule_in: 10)

      start_supervised_oban!(plugins: [{Stager, interval: 5}])

      with_backoff(fn ->
        assert %{state: "available"} = Repo.reload(job_1)
        assert %{state: "available"} = Repo.reload(job_2)
        assert %{state: "scheduled"} = Repo.reload(job_3)
      end)

      assert_receive {:event, :start, %{system_time: _}, %{conf: _, plugin: Stager}}
      assert_receive {:event, :stop, %{duration: _}, %{plugin: Stager} = meta}

      assert %{staged_count: 2, staged: [_ | _]} = meta
    end

    test "limiting the number of jobs staged at one time" do
      job_1 = insert!([ref: 1, action: "OK"], schedule_in: -60)
      job_2 = insert!([ref: 2, action: "OK"], schedule_in: -60)
      job_3 = insert!([ref: 3, action: "OK"], schedule_in: -60)

      name = start_supervised_oban!(plugins: [{Stager, limit: 1}])

      name
      |> Oban.Registry.whereis({:plugin, Stager})
      |> send(:stage)

      with_backoff(fn ->
        assert %{state: "available"} = Repo.reload(job_1)
        assert %{state: "scheduled"} = Repo.reload(job_2)
        assert %{state: "scheduled"} = Repo.reload(job_3)
      end)
    end

    @tag :capture_log
    test "switching to local mode without functional pubsub" do
      name = start_supervised_oban!(poll_interval: 2, notifier: Oban.Notifiers.Postgres)

      {:via, _, {_, prod_name}} = Oban.Registry.via(name, {:producer, "default"})

      Registry.register(Oban.Registry, prod_name, nil)

      assert_receive {:notification, :insert, %{"queue" => "default"}}
    end
  end
end
