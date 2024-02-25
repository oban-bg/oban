defmodule Oban.StagerTest do
  use Oban.Case, async: true

  alias Oban.{Notifier, Stager}
  alias Oban.TelemetryHandler

  test "broadcasting insert events on job insertion" do
    name = start_supervised_oban!(stage_interval: 10_000)

    Notifier.listen(name, :insert)

    Oban.insert(name, Worker.new(%{action: "OK", ref: 0}, queue: :alpha))

    Oban.insert_all(name, [
      Worker.new(%{action: "OK", ref: 1}, queue: :gamma),
      Worker.new(%{action: "OK", ref: 2}, queue: :delta)
    ])

    assert_receive {:notification, :insert, %{"queue" => "alpha"}}
    assert_receive {:notification, :insert, %{"queue" => "gamma"}}
    assert_receive {:notification, :insert, %{"queue" => "delta"}}
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
    :telemetry_test.attach_event_handlers(self(), [[:oban, :stager, :switch]])

    [stage_interval: 5, notifier: {Oban.Notifiers.Isolated, connected: false}]
    |> start_supervised_oban!()
    |> ping_sonar()

    assert_receive {[:oban, :stager, :switch], _, %{}, %{mode: :local}}
  end

  test "switching to local mode when solitary and not the leader" do
    :telemetry_test.attach_event_handlers(self(), [[:oban, :stager, :switch]])

    opts = [
      stage_interval: 5,
      notifier: Oban.Notifiers.Isolated,
      peer: {Oban.Peers.Isolated, leader?: false}
    ]

    opts
    |> start_supervised_oban!()
    |> ping_sonar()

    assert_receive {[:oban, :stager, :switch], _, %{}, %{mode: :local}}
  end

  test "dispatching directly to registered producers in local mode" do
    name =
      start_supervised_oban!(
        stage_interval: 5,
        notifier: Oban.Notifiers.Isolated,
        peer: {Oban.Peers.Isolated, leader?: false}
      )

    ping_sonar(name)

    with {:via, _, {_, prod_name}} <- Oban.Registry.via(name, {:producer, "staging_test"}) do
      Registry.register(Oban.Registry, prod_name, nil)
    end

    assert_receive {:notification, :insert, %{"queue" => "staging_test"}}
  end

  defp ping_sonar(name) do
    name
    |> Oban.Registry.whereis(Oban.Sonar)
    |> send(:ping)
  end
end
