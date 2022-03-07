defmodule Oban.Plugins.StagerTest do
  use Oban.Case

  alias Oban.Plugins.Stager
  alias Oban.{PluginTelemetryHandler, Registry}

  describe "validate/1" do
    test "validating numerical values" do
      assert {:error, _} = Stager.validate(interval: nil)
      assert {:error, _} = Stager.validate(interval: 0)

      assert :ok = Stager.validate(interval: 1)
      assert :ok = Stager.validate(interval: :timer.seconds(30))
    end
  end

  describe "integration" do
    @describetag :integration

    test "descheduling jobs to make them available for execution" do
      PluginTelemetryHandler.attach_plugin_events("plugin-stager-handler")

      then = DateTime.add(DateTime.utc_now(), -30)

      job_1 = insert!([ref: 1, action: "OK"], inserted_at: then, schedule_in: -9, queue: :alpha)
      job_2 = insert!([ref: 2, action: "OK"], inserted_at: then, schedule_in: -5, queue: :alpha)
      job_3 = insert!([ref: 3, action: "OK"], inserted_at: then, schedule_in: 10, queue: :alpha)

      name = start_supervised_oban!(plugins: [Stager])

      stage(name)

      with_backoff(fn ->
        assert %{state: "available"} = Repo.reload(job_1)
        assert %{state: "available"} = Repo.reload(job_2)
        assert %{state: "scheduled"} = Repo.reload(job_3)
      end)

      assert_receive {:event, :start, %{system_time: _}, %{conf: _, plugin: Stager}}
      assert_receive {:event, :stop, %{duration: _}, %{conf: _, plugin: Stager, staged_count: 2}}
    after
      :telemetry.detach("plugin-stager-handler")
    end

    test "limiting the number of jobs staged at one time" do
      job_1 = insert!([ref: 1, action: "OK"], schedule_in: -60)
      job_2 = insert!([ref: 2, action: "OK"], schedule_in: -60)
      job_3 = insert!([ref: 3, action: "OK"], schedule_in: -60)

      name = start_supervised_oban!(plugins: [{Stager, limit: 1}])

      stage(name)

      with_backoff(fn ->
        assert %{state: "available"} = Repo.reload(job_1)
        assert %{state: "scheduled"} = Repo.reload(job_2)
        assert %{state: "scheduled"} = Repo.reload(job_3)
      end)
    end

    test "translating poll_interval config into plugin usage" do
      assert []
             |> start_supervised_oban!()
             |> Registry.whereis({:plugin, Stager})

      assert [poll_interval: 2000]
             |> start_supervised_oban!()
             |> Registry.whereis({:plugin, Stager})

      refute [plugins: false, poll_interval: 2000]
             |> start_supervised_oban!()
             |> Registry.whereis({:plugin, Stager})
    end
  end

  defp stage(name) do
    name
    |> Registry.whereis({:plugin, Stager})
    |> send(:stage)
  end
end
