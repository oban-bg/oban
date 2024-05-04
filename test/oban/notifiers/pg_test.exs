defmodule Oban.Notifiers.PGTest do
  use Oban.Case, async: true

  alias Oban.Notifier
  alias Oban.Notifiers.PG

  describe "namespacing" do
    test "namespacing by configured prefix without an override" do
      name_1 = start_supervised_oban!(notifier: PG, prefix: "pg_test")
      name_2 = start_supervised_oban!(notifier: PG, prefix: "pg_test")

      await_joined("pg_test")

      :ok = Notifier.listen(name_1, :signal)
      :ok = Notifier.notify(name_2, :signal, %{incoming: "message"})

      assert_receive {:notification, :signal, %{"incoming" => "message"}}
    end

    test "overriding the default namespace" do
      name_1 = start_supervised_oban!(notifier: {PG, namespace: :pg_test}, prefix: "pg_a")
      name_2 = start_supervised_oban!(notifier: {PG, namespace: :pg_test}, prefix: "pg_b")

      await_joined(:pg_test)

      :ok = Notifier.listen(name_1, :signal)
      :ok = Notifier.notify(name_2, :signal, %{incoming: "message"})

      assert_receive {:notification, :signal, %{"incoming" => "message"}}
    end
  end

  defp await_joined(group) do
    # We can't use monitor_scope/1 because it's only available as of OTP 25. This does the trick
    # for now.
    case :pg.get_local_members(PG, group) do
      [] -> await_joined(group)
      _ -> :ok
    end
  end
end
