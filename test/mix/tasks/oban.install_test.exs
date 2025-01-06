defmodule Mix.Tasks.Oban.InstallTest do
  use ExUnit.Case, async: true

  import Igniter.Test

  describe "install" do
    test "installing without an available ecto repo" do
      assert {:error, [warning]} =
               test_project()
               |> Igniter.compose_task("oban.install", [])
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

      repo = """
      defmodule Oban.Test.Repo do
        @moduledoc false

        use MyApp.CustomMacro, otp_app: :oban

        use Ecto.Repo, otp_app: :oban, adapter: Ecto.Adapters.Postgres
      end
      """

      files = %{"lib/oban/application.ex" => application, "lib/oban/repo.ex" => repo}

      [app_name: :oban, files: files]
      |> test_project()
      |> Igniter.compose_task("oban.install", [])
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

    test "installing with an ash_postgres repo available" do
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

      repo = """
      defmodule Oban.Test.Repo do
        @moduledoc false

        use MyApp.CustomMacro, otp_app: :oban

        use AshPostgres.Repo, otp_app: :oban
      end
      """

      files = %{"lib/oban/application.ex" => application, "lib/oban/repo.ex" => repo}

      [app_name: :oban, files: files]
      |> test_project()
      |> Igniter.compose_task("oban.install", [])
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
      repo = """
      defmodule Oban.Test.LiteRepo do
        @moduledoc false

        use Ecto.Repo, otp_app: :oban, adapter: Ecto.Adapters.SQLite3
      end
      """

      [app_name: :oban, files: %{"lib/oban/repo.ex" => repo}]
      |> test_project()
      |> Igniter.compose_task("oban.install", ["--repo", "Oban.Test.LiteRepo"])
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
