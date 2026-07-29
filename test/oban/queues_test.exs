defmodule Oban.QueuesTest do
  use Oban.Case, async: true

  alias Oban.{Notifier, Queues, Registry}

  @moduletag :capture_log

  describe "notifier crash recovery" do
    test "queues resubscribe to the notifier after a crash" do
      name = start_supervised_oban!(notifier: Oban.Notifiers.Isolated)

      queues_pid = Registry.whereis(name, Queues)
      notifier_pid = Registry.whereis(name, Notifier)

      # Kill the notifier — Queues is under a different supervisor branch and survives.
      Process.exit(notifier_pid, :kill)

      with_backoff([sleep: 2], fn ->
        new_pid = Registry.whereis(name, Notifier)
        assert is_pid(new_pid) and new_pid != notifier_pid
      end)

      # Queues was not restarted
      assert Registry.whereis(name, Queues) == queues_pid

      # Nudge Queues to retry resubscription now that the notifier is up, bypassing
      # its 100ms backoff. send/2 is harmless if it has already resubscribed.
      send(queues_pid, :resubscribe)

      # Prove resubscription by sending a :signal to start a dynamic queue through
      # the new notifier. If Queues resubscribed, it receives the notification and
      # starts the queue.
      with_backoff([sleep: 2], fn ->
        Notifier.notify(name, :signal, %{action: "start", queue: "dynamic_test", limit: 1})
        assert is_pid(Registry.whereis(name, {:producer, "dynamic_test"}))
      end)
    end
  end
end
