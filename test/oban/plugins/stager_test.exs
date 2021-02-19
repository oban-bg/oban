defmodule Oban.Plugins.StagerTest do
  use Oban.Case

  alias Oban.Plugins.Stager
  alias Oban.{PluginTelemetryHandler, Registry}

  @moduletag :integration

  test "descheduling jobs to make them available for execution" do
    PluginTelemetryHandler.attach_plugin_events("plugin-stager-handler")

    then = DateTime.add(DateTime.utc_now(), -30)

    job_1 = insert!([ref: 1, action: "OK"], inserted_at: then, schedule_in: -9, queue: :alpha)
    job_2 = insert!([ref: 2, action: "OK"], inserted_at: then, schedule_in: -5, queue: :alpha)
    job_3 = insert!([ref: 3, action: "OK"], inserted_at: then, schedule_in: 10, queue: :alpha)

    start_supervised_oban!(plugins: [{Stager, interval: 10}])

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
