defmodule Oban.Notifiers.PGTest do
  use Oban.Case, async: true

  alias Oban.Notifier
  alias Oban.Notifiers.PG

  setup do
    :pg.start_link(Oban.Notifiers.PG)
    :pg.monitor_scope(Oban.Notifiers.PG)

    :ok
  end

  describe "namespacing" do
    test "namespacing by configured prefix without an override" do
      name_1 = start_supervised_oban!(notifier: PG, prefix: "pg_test")
      name_2 = start_supervised_oban!(notifier: PG, prefix: "pg_test")

      assert_joined("pg_test")
      assert_joined("pg_test")

      :ok = Notifier.listen(name_1, :signal)
      :ok = Notifier.notify(name_2, :signal, %{incoming: "message"})

      assert_receive {:notification, :signal, %{"incoming" => "message"}}
    end

    test "overriding the default namespace" do
      name_1 = start_supervised_oban!(notifier: {PG, namespace: :pg_test}, prefix: "pg_a")
      name_2 = start_supervised_oban!(notifier: {PG, namespace: :pg_test}, prefix: "pg_b")

      assert_joined(:pg_test)
      assert_joined(:pg_test)

      :ok = Notifier.listen(name_1, :signal)
      :ok = Notifier.notify(name_2, :signal, %{incoming: "message"})

      assert_receive {:notification, :signal, %{"incoming" => "message"}}
    end
  end

  defp assert_joined(group) do
      assert_receive {_ref, :join, ^group, _pids}
  end
end
