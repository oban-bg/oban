defmodule Oban.Notifiers.ListenersTest do
  use Oban.Case, async: true

  alias Oban.Notifier
  alias Oban.Notifiers.Listeners

  @moduletag :capture_log

  test "registering the same channel repeatedly records a single listener" do
    name = start_oban!()
    conf = Oban.config(name)

    :ok = Notifier.listen(name, :gossip)
    :ok = Notifier.listen(name, :gossip)

    assert [self()] == Listeners.listeners(conf, :gossip)
  end

  test "unregistering removes the listener and the channel" do
    name = start_oban!()
    conf = Oban.config(name)

    :ok = Notifier.listen(name, [:gossip, :signal])
    :ok = Notifier.unlisten(name, :gossip)

    assert [] == Listeners.listeners(conf, :gossip)
    assert :signal in Listeners.channels(conf)
    refute :gossip in Listeners.channels(conf)
  end

  test "listener registrations are removed when the listener exits" do
    name = start_oban!()
    conf = Oban.config(name)

    {:ok, pid} =
      Task.start(fn ->
        :ok = Notifier.listen(name, :gossip)

        receive do
          :stop -> :ok
        end
      end)

    with_backoff(fn -> assert pid in Listeners.listeners(conf, :gossip) end)

    send(pid, :stop)

    with_backoff(fn -> refute pid in Listeners.listeners(conf, :gossip) end)
  end

  test "listening while the notifier is unavailable still registers" do
    name = start_oban!()
    conf = Oban.config(name)

    # Race the restart: the registration lands regardless of whether the call reaches the dying
    # notifier, the restarting notifier, or nothing at all.
    Process.exit(Oban.Registry.whereis(name, Notifier), :kill)

    :ok = Notifier.listen(name, :gossip)

    assert self() in Listeners.listeners(conf, :gossip)
  end

  defp start_oban!, do: start_supervised_oban!(notifier: Oban.Notifiers.Isolated)
end
