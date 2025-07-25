defmodule Oban.MixProject do
  use Mix.Project

  @source_url "https://github.com/oban-bg/oban"
  @version "2.19.4"

  def project do
    [
      app: :oban,
      version: @version,
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      xref: [exclude: [Postgrex.Error, MyXQL.Error]],

      # Hex
      package: package(),
      description: """
      Robust job processing, backed by modern PostgreSQL, SQLite3, and MySQL.
      """,

      # Dialyzer
      dialyzer: [
        plt_add_apps: [:ex_unit, :mix, :postgrex],
        plt_core_path: "_build/#{Mix.env()}",
        flags: [:error_handling, :missing_return, :underspecs]
      ],

      # Docs
      name: "Oban",
      docs: [
        main: "Oban",
        api_reference: false,
        logo: "assets/oban-logo.svg",
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

  def cli do
    [preferred_envs: [bench: :test, "test.ci": :test, "test.reset": :test, "test.setup": :test]]
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
      # Introduction
      "guides/introduction/installation.md",
      "guides/introduction/ready_for_production.md",

      # Learning
      "guides/learning/defining_queues.md",
      "guides/learning/job_lifecycle.md",
      "guides/learning/scheduling_jobs.md",
      "guides/learning/periodic_jobs.md",
      "guides/learning/unique_jobs.md",
      "guides/learning/operational_maintenance.md",
      "guides/learning/instrumentation.md",
      "guides/learning/error_handling.md",
      "guides/learning/clustering.md",
      "guides/learning/isolation.md",

      # Advanced
      "guides/advanced/writing_plugins.md",
      "guides/advanced/release_configuration.md",
      "guides/advanced/scaling.md",
      "guides/advanced/troubleshooting.md",

      # Upgrading
      "guides/upgrading/v2.0.md",
      "guides/upgrading/v2.6.md",
      "guides/upgrading/v2.11.md",
      "guides/upgrading/v2.12.md",
      "guides/upgrading/v2.14.md",
      "guides/upgrading/v2.17.md",

      # Recipes
      "guides/recipes/recursive-jobs.md",
      "guides/recipes/reliable-scheduling.md",
      "guides/recipes/reporting-progress.md",
      "guides/recipes/expected-failures.md",
      "guides/recipes/splitting-queues.md",
      "guides/recipes/migrating-from-other-languages.md",

      # Testing
      "guides/testing/testing.md",
      "guides/testing/testing_workers.md",
      "guides/testing/testing_queues.md",
      "guides/testing/testing_config.md",
      "CHANGELOG.md": [title: "Changelog"]
    ]
  end

  defp groups_for_extras do
    [
      External: ~r{https:},
      Introduction: ~r{guides/introduction/[^\/]+\.md},
      Learning: ~r{guides/learning/[^\/]+\.md},
      Advanced: ~r{guides/advanced/[^\/]+\.md},
      Recipes: ~r{guides/recipes/.?},
      Testing: ~r{guides/testing/.?},
      Upgrading: ~r{guides/upgrading/.*}
    ]
  end

  defp groups_for_modules do
    [
      Plugins: [
        Oban.Plugin,
        Oban.Plugins.Cron,
        Oban.Plugins.Lifeline,
        Oban.Plugins.Pruner,
        Oban.Plugins.Reindexer
      ],
      Extending: [
        Oban.Config,
        Oban.Registry,
        Oban.Repo,
        Oban.Telemetry
      ],
      Notifiers: [
        Oban.Notifier,
        Oban.Notifiers.Postgres,
        Oban.Notifiers.PG
      ],
      Peers: [
        Oban.Peer,
        Oban.Peers.Database,
        Oban.Peers.Global
      ],
      Engines: [
        Oban.Engine,
        Oban.Engines.Basic,
        Oban.Engines.Dolphin,
        Oban.Engines.Inline,
        Oban.Engines.Lite
      ]
    ]
  end

  defp package do
    [
      maintainers: ["Parker Selbert"],
      licenses: ["Apache-2.0"],
      files: ~w(lib .formatter.exs mix.exs README* CHANGELOG* LICENSE*),
      links: %{
        Website: "https://oban.pro",
        Changelog: "#{@source_url}/blob/main/CHANGELOG.md",
        GitHub: @source_url
      }
    ]
  end

  defp deps do
    [
      {:ecto_sql, "~> 3.10"},
      {:telemetry, "~> 1.3"},

      # Optional
      {:ecto_sqlite3, "~> 0.9", optional: true},
      {:jason, "~> 1.1", optional: true},
      {:igniter, "~> 0.5", optional: true},
      {:myxql, "~> 0.7", optional: true},
      {:postgrex, "~> 0.20", optional: true},

      # Test and Dev
      {:stream_data, "~> 1.0", only: [:test, :dev]},
      {:tz, "~> 0.24", only: [:test, :dev]},
      {:benchee, "~> 1.4", only: [:test, :dev], runtime: false},
      {:credo, "~> 1.7", only: [:test, :dev], runtime: false},
      {:dialyxir, "~> 1.4", only: [:test, :dev], runtime: false},
      {:ex_doc, "~> 0.38", only: [:test, :dev], runtime: false},
      {:makeup_diff, "~> 0.1", only: [:test, :dev], runtime: false}
    ]
  end

  defp aliases do
    [
      bench: "run bench/bench_helper.exs",
      release: [
        "cmd git tag v#{@version}",
        "cmd git push",
        "cmd git push --tags",
        "hex.publish --yes"
      ],
      "test.reset": ["ecto.drop --quiet", "test.setup"],
      "test.setup": ["ecto.create --quiet", "ecto.migrate --quiet"],
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
