defmodule Oban.SonarTest do
  use Oban.Case, async: true

  alias Oban.Notifier

  describe "integration" do
    test "remaining isolated without any notifications" do
      name = start_supervised_oban!(notifier: Oban.Notifiers.Postgres)

      assert :isolated = Notifier.status(name)
    end

    test "reporting a solitary status with only a single node" do
      name = start_supervised_oban!(notifier: Oban.Notifiers.Isolated)

      with_backoff(fn ->
        assert :solitary = Notifier.status(name)
      end)
    end

    test "reporting a clustered status with multiple nodes" do
      name = start_supervised_oban!(notifier: Oban.Notifiers.Isolated)

      Notifier.notify(name, :sonar, %{node: "web.1", ping: :ping})

      with_backoff(fn ->
        assert :clustered = Notifier.status(name)
      end)
    end
  end
end
