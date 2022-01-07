defmodule Oban.Plugins.LifelineTest do
  use Oban.Case, async: true

  alias Oban.Plugins.Lifeline
  alias Oban.PluginTelemetryHandler

  setup do
    PluginTelemetryHandler.attach_plugin_events("plugin-lifeline-handler")

    on_exit(fn ->
      :telemetry.detach("plugin-lifeline-handler")
    end)
  end

  test "rescuing executing jobs older than the rescue window" do
    name = start_supervised_oban!(plugins: [{Lifeline, interval: 10, rescue_after: 5_000}])

    job_a = insert!(%{}, state: "executing", attempted_at: seconds_ago(4))
    job_b = insert!(%{}, state: "executing", attempted_at: seconds_ago(6))
    job_c = insert!(%{}, state: "executing", attempted_at: seconds_ago(7), attempt: 20)

    assert %{state: "executing"} = Repo.reload(job_a)
    assert %{state: "available"} = Repo.reload(job_b)
    assert %{state: "discarded"} = Repo.reload(job_c)

    assert_receive {:event, :start, _meta, %{plugin: Lifeline}}
    assert_receive {:event, :stop, _meta, %{plugin: Lifeline, rescued_count: 2}}

    stop_supervised(name)
  end
end
