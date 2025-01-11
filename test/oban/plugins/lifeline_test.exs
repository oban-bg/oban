defmodule Oban.Plugins.LifelineTest do
  use Oban.Case, async: true

  alias Oban.Plugins.Lifeline
  alias Oban.TelemetryHandler
  alias Oban.Test.DolphinRepo

  describe "validate/1" do
    test "validating interval options" do
      assert {:error, _} = Lifeline.validate(interval: 0)
      assert {:error, _} = Lifeline.validate(rescue_after: 0)

      assert :ok = Lifeline.validate(interval: :timer.seconds(30))
      assert :ok = Lifeline.validate(rescue_after: :timer.minutes(30))
    end

    test "providing suggestions for unknown options" do
      assert {:error, "unknown option :inter, did you mean :interval?"} =
               Lifeline.validate(inter: 1)
    end
  end

  describe "integration" do
    setup do
      TelemetryHandler.attach_events()
    end

    test "rescuing executing jobs older than the rescue window" do
      name = start_supervised_oban!(plugins: [{Lifeline, rescue_after: 5_000}])

      job_1 = insert!(%{}, state: "executing", attempted_at: seconds_ago(3))
      job_2 = insert!(%{}, state: "executing", attempted_at: seconds_ago(7))
      job_3 = insert!(%{}, state: "executing", attempted_at: seconds_ago(8), attempt: 20)

      send_rescue(name)

      assert_receive {:event, :start, _measure, %{plugin: Lifeline}}
      assert_receive {:event, :stop, _measure, %{plugin: Lifeline} = meta}

      assert %{rescued_jobs: [_]} = meta
      assert %{discarded_jobs: [_]} = meta

      assert %{state: "executing"} = Repo.reload(job_1)
      assert %{state: "available"} = Repo.reload(job_2)
      assert %{state: "discarded"} = Repo.reload(job_3)

      stop_supervised(name)
    end

    test "rescuing jobs within a custom prefix" do
      name = start_supervised_oban!(prefix: "private", plugins: [{Lifeline, rescue_after: 5_000}])

      job_1 = insert!(name, %{}, state: "executing", attempted_at: seconds_ago(1))
      job_2 = insert!(name, %{}, state: "executing", attempted_at: seconds_ago(7))

      send_rescue(name)

      assert_receive {:event, :stop, _meta, %{plugin: Lifeline, rescued_jobs: [_]}}

      assert %{state: "executing"} = Repo.reload(job_1)
      assert %{state: "available"} = Repo.reload(job_2)

      stop_supervised(name)
    end
  end

  describe "compatibility" do
    setup do
      TelemetryHandler.attach_events()
    end

    @tag :dolphin
    test "rescuing stuck jobs using the Dolphin engine" do
      name =
        start_supervised_oban!(
          engine: Oban.Engines.Dolphin,
          plugins: [{Lifeline, rescue_after: 5_000}],
          repo: DolphinRepo
        )

      job_1 =
        Oban.insert!(name, Worker.new(%{}, state: "executing", attempted_at: seconds_ago(3)))

      job_2 =
        Oban.insert!(name, Worker.new(%{}, state: "executing", attempted_at: seconds_ago(8)))

      send_rescue(name)

      assert_receive {:event, :stop, _meta, %{plugin: Lifeline, rescued_jobs: [_]}}

      assert %{state: "executing"} = DolphinRepo.reload(job_1)
      assert %{state: "available"} = DolphinRepo.reload(job_2)

      stop_supervised(name)
    end
  end

  defp send_rescue(name) do
    name
    |> Oban.Registry.whereis({:plugin, Lifeline})
    |> send(:rescue)
  end
end
