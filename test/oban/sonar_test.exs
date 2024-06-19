defmodule Oban.SonarTest do
  use Oban.Case, async: true

  alias Oban.{Notifier, Registry, Sonar}

  describe "integration" do
    setup do
      :telemetry_test.attach_event_handlers(self(), [[:oban, :notifier, :switch]])

      :ok
    end

    test "starting with an :unknown status" do
      name = start_supervised_oban!(notifier: Oban.Notifiers.Postgres)

      assert :unknown = Notifier.status(name)
    end

    test "remaining isolated without any notifications" do
      name = start_supervised_oban!(notifier: Oban.Notifiers.Postgres)

      name
      |> Registry.whereis(Sonar)
      |> send(:ping)

      with_backoff(fn ->
        assert :isolated = Notifier.status(name)
      end)

      assert_received {_event, _ref, _timing, %{status: :isolated}}
    end

    test "reporting a solitary status with only a single node" do
      name = start_supervised_oban!(notifier: Oban.Notifiers.Isolated)

      with_backoff(fn ->
        assert :solitary = Notifier.status(name)
      end)

      assert_received {_event, _ref, _timing, %{status: :solitary}}
    end

    test "reporting a clustered status with multiple nodes" do
      name = start_supervised_oban!(notifier: Oban.Notifiers.Isolated)

      Notifier.notify(name, :sonar, %{node: "web.1"})

      with_backoff(fn ->
        assert :clustered = Notifier.status(name)
      end)

      assert_received {_event, _ref, _timing, %{status: :clustered}}
    end

    test "pruning stale nodes based on the last notification time" do
      name = start_supervised_oban!(notifier: Oban.Notifiers.Isolated)
      time = System.monotonic_time(:millisecond)

      Notifier.notify(name, :sonar, %{node: "web.1", time: time + :timer.seconds(29)})
      Notifier.notify(name, :sonar, %{node: "web.2", time: time + :timer.seconds(31)})

      nodes =
        name
        |> Registry.whereis(Sonar)
        |> GenServer.call(:prune_nodes)

      assert "web.1" in nodes
      refute "web.2" in nodes
    end
  end
end
