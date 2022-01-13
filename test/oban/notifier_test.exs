defmodule Oban.NotifierTest do
  use Oban.Case

  alias Oban.Notifier

  @opts [notifier: Oban.Notifiers.Postgres]

  describe "listen/notify" do
    test "notifying with complex types" do
      name = start_supervised_oban!(@opts)

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
      name = start_supervised_oban!(@opts)

      :ok = Notifier.listen(name, [:signal, :gossip])
      :ok = Notifier.unlisten(name, [:gossip])

      :ok = Notifier.notify(name, :gossip, %{foo: "bar"})
      :ok = Notifier.notify(name, :signal, %{baz: "bat"})

      refute_receive {:notification, :gossip, _}
      assert_receive {:notification, :signal, _}
    end

    test "ignoring messages scoped to other instances" do
      name = start_supervised_oban!(@opts)

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
