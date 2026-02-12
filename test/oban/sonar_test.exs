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

      Notifier.notify(name, :sonar, %{node: "web.0", time: time - :timer.seconds(10)})
      Notifier.notify(name, :sonar, %{node: "web.1", time: time - :timer.seconds(29)})
      Notifier.notify(name, :sonar, %{node: "web.2", time: time - :timer.seconds(31)})

      nodes =
        name
        |> Registry.whereis(Sonar)
        |> GenServer.call(:prune_nodes)

      assert "web.1" in nodes
      refute "web.2" in nodes
    end
  end

  describe "notifier crash recovery" do
    @tag :capture_log
    test "sonar re-registers as listener after notifier crash" do
      name = start_supervised_oban!(notifier: Oban.Notifiers.Isolated)

      with_backoff(fn ->
        assert :solitary = Notifier.status(name)
      end)

      sonar_pid = Registry.whereis(name, Sonar)
      notifier_pid = Registry.whereis(name, Notifier)
      Process.exit(notifier_pid, :kill)

      # Wait for the notifier to restart with a new pid.
      with_backoff(fn ->
        new_pid = Registry.whereis(name, Notifier)
        assert is_pid(new_pid) and new_pid != notifier_pid
      end)

      # Sonar was not restarted
      assert Registry.whereis(name, Sonar) == sonar_pid

      # Trigger a ping to re-register Sonar as a listener.
      GenServer.call(sonar_pid, :ping)

      # Send a notification from a fake external node. If Sonar re-registered as
      # a listener on the new notifier, it receives this and becomes :clustered.
      # Without re-registration the notification goes nowhere.
      Notifier.notify(name, :sonar, %{node: "external.1"})

      with_backoff(fn ->
        assert :clustered = Notifier.status(name)
      end)
    end
  end
end
