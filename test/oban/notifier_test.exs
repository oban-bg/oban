defmodule Oban.NotifierTest do
  use Oban.Case, async: true

  alias Oban.{Config, Notifier}
  alias Oban.Notifiers.{PG, Postgres}

  test "resubscribing to channels after a disconnect" do
    conf = Config.new(repo: Repo)

    {:ok, pid} = Postgres.start_link(conf: conf, name: __MODULE__)

    assert :ok = Postgres.listen(pid, [:gossip])

    disconnect_and_reconnect(pid)

    assert :ok = Postgres.listen(pid, [:signal])
  end

  for notifier <- [PG, Postgres] do
    @notifier notifier

    describe "using #{notifier}" do
      test "broadcasting notifications to subscribers" do
        name = start_supervised_oban!(notifier: @notifier)

        :ok = Notifier.listen(name, [:signal])
        :ok = Notifier.notify(name, :signal, %{incoming: "message"})

        assert_receive {:notification, :signal, %{"incoming" => "message"}}
      end

      test "notifying with complex types" do
        name = start_supervised_oban!(notifier: @notifier)

        Notifier.listen(name, [:insert, :gossip, :signal])

        Notifier.notify(name, :signal, %{
          date: ~D[2021-08-09],
          keyword: [a: 1, b: 1],
          map: %{tuple: {1, :second}},
          tuple: {1, :second}
        })

        assert_receive {:notification, :signal, notice}
        assert %{"date" => "2021-08-09", "keyword" => [["a", 1], ["b", 1]]} = notice
        assert %{"map" => %{"tuple" => [1, "second"]}, "tuple" => [1, "second"]} = notice

        stop_supervised(name)
      end

      test "broadcasting on select channels" do
        name = start_supervised_oban!(notifier: @notifier)

        :ok = Notifier.listen(name, [:signal, :gossip])
        :ok = Notifier.unlisten(name, [:gossip])

        :ok = Notifier.notify(name, :gossip, %{foo: "bar"})
        :ok = Notifier.notify(name, :signal, %{baz: "bat"})

        refute_receive {:notification, :gossip, _}
        assert_receive {:notification, :signal, _}
      end

      test "ignoring messages scoped to other instances" do
        name = start_supervised_oban!(notifier: @notifier)

        :ok = Notifier.listen(name, [:gossip, :signal])

        ident =
          name
          |> Oban.config()
          |> Config.to_ident()

        :ok = Notifier.notify(name, :gossip, %{foo: "bar", ident: ident})
        :ok = Notifier.notify(name, :signal, %{foo: "baz", ident: "bogus.ident"})

        assert_receive {:notification, :gossip, _}
        refute_receive {:notification, :signal, _}

        stop_supervised(name)
      end
    end
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
