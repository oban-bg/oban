defmodule Oban.SonarTest do
  use Oban.Case, async: true

  alias Oban.{Notifier, Sonar}

  describe "integration" do
    test "remaining disconnected without any notifications" do
      name = start_supervised_oban!(notifier: Oban.Notifiers.Postgres)

      assert :disconnected = Sonar.status(name)
    end

    test "reporting an isolated status with only a single node" do
      name = start_supervised_oban!(notifier: Oban.Notifiers.Isolated)

      with_backoff(fn ->
        assert :isolated = Sonar.status(name)
      end)
    end

    test "reporting a clustered status with multiple nodes" do
      name = start_supervised_oban!(notifier: Oban.Notifiers.Isolated)

      Notifier.notify(name, :sonar, %{node: "web.1", ping: :ping})

      with_backoff(fn ->
        assert :clustered = Sonar.status(name)
      end)
    end
  end
end
