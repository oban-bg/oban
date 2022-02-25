defmodule Oban.Notifiers.PostgresTest do
  use Oban.Case, async: true

  alias Oban.Config
  alias Oban.Notifiers.Postgres

  test "resubscribing to channels after a disconnect" do
    conf = Config.new(repo: Repo)

    {:ok, pid} = Postgres.start_link(conf: conf, name: __MODULE__)

    assert :ok = Postgres.listen(pid, [:gossip])

    disconnect_and_reconnect(pid)

    assert :ok = Postgres.listen(pid, [:signal])
  end

  # This is based on connection tests within postgrex itself. It is invasive and relies on
  # internal attributes, but it's the only known mechanism to get the underlying socket.
  defp disconnect_and_reconnect(pid) do
    {:gen_tcp, sock} = :sys.get_state(pid).mod_state.protocol.sock

    :gen_tcp.shutdown(sock, :read_write)

    # Give the notifier a chance to re-establish the connection and listeners
    Process.sleep(250)
  end
end
