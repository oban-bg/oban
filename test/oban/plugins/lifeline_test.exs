defmodule Oban.Plugins.LifelineTest do
  use Oban.Case, async: true

  alias Oban.Plugins.Lifeline
  alias Oban.TelemetryHandler

  describe "validate/1" do
    test "validating interval options" do
      assert {:error, _} = Lifeline.validate(interval: 0)
      assert {:error, _} = Lifeline.validate(rescue_after: 0)

      assert :ok = Lifeline.validate(interval: :timer.seconds(30))
      assert :ok = Lifeline.validate(rescue_after: :timer.minutes(30))
    end
  end

  describe "integration" do
    setup do
      TelemetryHandler.attach_events()
    end

    test "rescuing executing jobs older than the rescue window" do
      name = start_supervised_oban!(plugins: [{Lifeline, rescue_after: 5_000}])

      job_a = insert!(%{}, state: "executing", attempted_at: seconds_ago(3))
      job_b = insert!(%{}, state: "executing", attempted_at: seconds_ago(7))
      job_c = insert!(%{}, state: "executing", attempted_at: seconds_ago(8), attempt: 20)

      send_rescue(name)

      assert_receive {:event, :start, _measure, %{plugin: Lifeline}}
      assert_receive {:event, :stop, _measure, %{plugin: Lifeline} = meta}

      assert %{rescued_count: 1, rescued_jobs: [_ | _]} = meta
      assert %{discarded_count: 1, discarded_jobs: [_ | _]} = meta

      assert %{state: "executing"} = Repo.reload(job_a)
      assert %{state: "available"} = Repo.reload(job_b)
      assert %{state: "discarded"} = Repo.reload(job_c)

      stop_supervised(name)
    end

    test "rescuing jobs within a custom prefix" do
      name = start_supervised_oban!(prefix: "private", plugins: [{Lifeline, rescue_after: 5_000}])

      job_a = insert!(name, %{}, state: "executing", attempted_at: seconds_ago(1))
      job_b = insert!(name, %{}, state: "executing", attempted_at: seconds_ago(7))

      send_rescue(name)

      assert_receive {:event, :stop, _meta, %{plugin: Lifeline, rescued_count: 1}}

      assert %{state: "executing"} = Repo.reload(job_a)
      assert %{state: "available"} = Repo.reload(job_b)

      stop_supervised(name)
    end
  end

  defp send_rescue(name) do
    name
    |> Oban.Registry.whereis({:plugin, Lifeline})
    |> send(:rescue)
  end
end
