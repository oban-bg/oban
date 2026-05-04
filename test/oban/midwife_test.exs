defmodule Oban.MidwifeTest do
  use Oban.Case, async: true

  alias Oban.{Midwife, Notifier, Registry}

  @moduletag :capture_log

  describe "notifier crash recovery" do
    test "midwife resubscribes to notifier after crash" do
      name = start_supervised_oban!(notifier: Oban.Notifiers.Isolated)

      midwife_pid = Registry.whereis(name, Midwife)
      notifier_pid = Registry.whereis(name, Notifier)

      # Kill the notifier — Midwife is under a different supervisor branch and survives.
      Process.exit(notifier_pid, :kill)

      with_backoff([sleep: 2], fn ->
        new_pid = Registry.whereis(name, Notifier)
        assert is_pid(new_pid) and new_pid != notifier_pid
      end)

      # Midwife was not restarted
      assert Registry.whereis(name, Midwife) == midwife_pid

      # Nudge Midwife to retry resubscription now that the notifier is up, bypassing
      # its 100ms backoff. send/2 is harmless if it has already resubscribed.
      send(midwife_pid, :resubscribe)

      # Prove resubscription by sending a :signal to start a dynamic queue through
      # the new notifier. If Midwife resubscribed, it receives the notification and
      # starts the queue.
      with_backoff([sleep: 2], fn ->
        Notifier.notify(name, :signal, %{action: "start", queue: "dynamic_test", limit: 1})
        assert is_pid(Registry.whereis(name, {:producer, "dynamic_test"}))
      end)
    end
  end
end
