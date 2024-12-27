defmodule Mix.Tasks.Oban.InstallTest do
  use ExUnit.Case, async: true

  import Igniter.Test

  alias Mix.Tasks.Oban.Install

  describe "install" do
    test "installing without an available ecto repo" do
      assert {:error, [warning]} =
               test_project()
               |> Install.igniter()
               |> apply_igniter()

      assert warning =~ "No ecto repos found for :test"
    end

    test "installing with an ecto repo available" do
      application = """
      defmodule Oban.Application do
        use Application

        def start(_type, _args) do
          children = [
            Oban.Test.Repo,
            {Ecto.Migrator, migrator_opts()},
            MyWeb.Endpoint
          ]
        end
      end
      """

      [app_name: :oban, files: %{"lib/oban/application.ex" => application}]
      |> test_project()
      |> Install.igniter()
      |> assert_has_patch("config/config.exs", """
        | config :oban, Oban,
        |   engine: Oban.Engines.Basic,
        |   notifier: Oban.Notifiers.Postgres,
        |   queues: [default: 10],
        |   repo: Oban.Test.Repo
      """)
      |> assert_has_patch("config/test.exs", """
        | config :oban, Oban, testing: :manual
      """)
      |> assert_has_patch("lib/oban/application.ex", """
        | {Oban, Application.fetch_env!(:oban, Oban)},
        | MyWeb.Endpoint
      """)
    end

    test "installing selects correct config with alternate repo" do
      [app_name: :oban]
      |> test_project()
      |> Map.replace!(:args, %{options: [repo: "Oban.Test.LiteRepo"]})
      |> Install.igniter()
      |> assert_has_patch("config/config.exs", """
        | config :oban, Oban,
        |   engine: Oban.Engines.Lite,
        |   notifier: Oban.Notifiers.PG,
        |   queues: [default: 10],
        |   repo: Oban.Test.LiteRepo
      """)
    end
  end
end
