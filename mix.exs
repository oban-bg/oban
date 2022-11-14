defmodule Oban.MixProject do
  use Mix.Project

  @source_url "https://github.com/sorentwo/oban"
  @version "2.13.5"

  def project do
    [
      app: :oban,
      version: @version,
      elixir: "~> 1.11",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      preferred_cli_env: [
        bench: :test,
        "test.ci": :test,
        "test.reset": :test,
        "test.setup": :test
      ],

      # Hex
      package: package(),
      description: """
      Robust job processing, backed by modern PostgreSQL.
      """,

      # Dialyzer
      dialyzer: [
        plt_add_apps: [:ex_unit],
        plt_core_path: "_build/#{Mix.env()}",
        flags: [:error_handling, :underspecs]
      ],

      # Docs
      name: "Oban",
      docs: [
        main: "Oban",
        logo: "assets/oban-logo.png",
        source_ref: "v#{@version}",
        source_url: @source_url,
        extra_section: "GUIDES",
        formatters: ["html"],
        extras: extras(),
        groups_for_extras: groups_for_extras(),
        groups_for_modules: groups_for_modules(),
        skip_undefined_reference_warnings_on: ["CHANGELOG.md"]
      ]
    ]
  end

  def application do
    [
      mod: {Oban.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp extras do
    [
      "CHANGELOG.md",

      # Guides
      "guides/installation.md",
      "guides/troubleshooting.md",
      "guides/release_configuration.md",
      "guides/writing_plugins.md",
      "guides/upgrading/v2.0.md",
      "guides/upgrading/v2.6.md",
      "guides/upgrading/v2.11.md",
      "guides/upgrading/v2.12.md",

      # Recipes
      "guides/recipes/recursive-jobs.md",
      "guides/recipes/reliable-scheduling.md",
      "guides/recipes/reporting-progress.md",
      "guides/recipes/expected-failures.md",
      "guides/recipes/splitting-queues.md",

      # Testing
      "guides/testing/testing.md",
      "guides/testing/testing_workers.md",
      "guides/testing/testing_queues.md",
      "guides/testing/testing_config.md"
    ]
  end

  defp groups_for_extras do
    [
      Guides: ~r{guides/[^\/]+\.md},
      Recipes: ~r{guides/recipes/.?},
      Testing: ~r{guides/testing/.?},
      "Upgrade Guides": ~r{guides/upgrading/.*}
    ]
  end

  defp groups_for_modules do
    [
      Plugins: [
        Oban.Plugins.Cron,
        Oban.Plugins.Gossip,
        Oban.Plugins.Lifeline,
        Oban.Plugins.Pruner,
        Oban.Plugins.Reindexer,
        Oban.Plugins.Repeater,
        Oban.Plugins.Stager
      ],
      Extending: [
        Oban.Config,
        Oban.Engine,
        Oban.Notifier,
        Oban.Peer,
        Oban.Plugin,
        Oban.Registry,
        Oban.Repo
      ],
      Notifiers: [
        Oban.Notifiers.Postgres,
        Oban.Notifiers.PG
      ],
      Peers: [
        Oban.Peers.Postgres,
        Oban.Peers.Global
      ]
    ]
  end

  defp package do
    [
      maintainers: ["Parker Selbert"],
      licenses: ["Apache-2.0"],
      links: %{
        Website: "https://getoban.pro",
        Changelog: "#{@source_url}/blob/main/CHANGELOG.md",
        GitHub: @source_url,
        Sponsor: "https://getoban.pro"
      }
    ]
  end

  defp deps do
    [
      {:ecto_sql, "~> 3.6"},
      {:jason, "~> 1.1"},
      {:postgrex, "~> 0.16"},
      {:telemetry, "~> 0.4 or ~> 1.0"},
      {:stream_data, "~> 0.4", only: [:test, :dev]},
      {:tzdata, "~> 1.0", only: [:test, :dev]},
      {:benchee, "~> 1.0", only: [:test, :dev], runtime: false},
      {:credo, "~> 1.6", only: [:test, :dev], runtime: false},
      {:dialyxir, "~> 1.0", only: [:test, :dev], runtime: false},
      {:ex_doc, "~> 0.28", only: [:test, :dev], runtime: false},
      {:makeup_diff, "~> 0.1", only: [:test, :dev], runtime: false}
    ]
  end

  defp aliases do
    [
      bench: "run bench/bench_helper.exs",
      "test.reset": ["ecto.drop", "test.setup"],
      "test.setup": ["ecto.create", "ecto.migrate"],
      "test.ci": [
        "format --check-formatted",
        "deps.unlock --check-unused",
        "credo --strict",
        "test --raise",
        "dialyzer"
      ]
    ]
  end
end
