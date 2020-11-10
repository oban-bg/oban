defmodule Oban.MixProject do
  use Mix.Project

  @version "2.3.3"

  def project do
    [
      app: :oban,
      version: @version,
      elixir: "~> 1.8",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      preferred_cli_env: [
        bench: :test,
        ci: :test,
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
        flags: [:error_handling, :race_conditions, :underspecs]
      ],

      # Docs
      name: "Oban",
      docs: [
        main: "Oban",
        source_ref: "v#{@version}",
        source_url: "https://github.com/sorentwo/oban",
        extra_section: "GUIDES",
        formatters: ["html"],
        extras: extras() ++ pro_extras() ++ web_extras(),
        groups_for_extras: groups_for_extras()
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
      "guides/installation.md",
      "guides/troubleshooting.md",
      "guides/writing_plugins.md",
      "guides/upgrading/v2.0.md",
      "guides/release_configuration.md",
      "guides/recipes/recursive-jobs.md",
      "guides/recipes/reliable-scheduling.md",
      "guides/recipes/reporting-progress.md",
      "guides/recipes/expected-failures.md",
      "guides/recipes/splitting-queues.md"
    ]
  end

  defp pro_extras do
    if File.exists?("../oban_pro") do
      [
        "../oban_pro/guides/pro/overview.md": [filename: "pro_overview"],
        "../oban_pro/guides/pro/installation.md": [filename: "pro_installation"],
        "../oban_pro/guides/plugins/lifeline.md": [title: "Lifeline Plugin"],
        "../oban_pro/guides/plugins/dynamic_cron.md": [title: "Dynamic Cron Plugin"],
        "../oban_pro/guides/plugins/dynamic_pruner.md": [title: "Dynamic Pruner Plugin"],
        "../oban_pro/guides/plugins/reprioritizer.md": [title: "Reprioritizer Plugin"],
        "../oban_pro/guides/workers/batch.md": [title: "Batch Worker"],
        "../oban_pro/guides/workers/workflow.md": [title: "Workflow Worker"],
        "../oban_pro/CHANGELOG.md": [filename: "pro-changelog", title: "Changelog"]
      ]
    else
      []
    end
  end

  defp web_extras do
    if File.exists?("../oban_web") do
      [
        "../oban_web/guides/web/overview.md": [filename: "web_overview"],
        "../oban_web/guides/web/installation.md": [filename: "web_installation"],
        "../oban_web/guides/web/troubleshooting.md": [filename: "web_troubleshooting"],
        "../oban_web/CHANGELOG.md": [filename: "web-changelog", title: "Changelog"]
      ]
    else
      []
    end
  end

  defp groups_for_extras do
    [
      Guides: ~r{guides/[^\/]+\.md},
      Recipes: ~r{guides/recipes/.?},
      Extras: ~r{^CHANGELOG.md},
      "Upgrade Guides": ~r{guides/upgrading/.*},
      "Oban Pro": ~r{oban_pro/.?},
      "Oban Web": ~r{oban_web/.?}
    ]
  end

  defp package do
    [
      maintainers: ["Parker Selbert"],
      licenses: ["Apache-2.0"],
      links: %{
        Website: "https://getoban.pro",
        Changelog: "https://github.com/sorentwo/oban/blob/master/CHANGELOG.md",
        GitHub: "https://github.com/sorentwo/oban"
      }
    ]
  end

  defp deps do
    [
      {:ecto_sql, ">= 3.4.3"},
      {:jason, "~> 1.1"},
      {:postgrex, "~> 0.14"},
      {:telemetry, "~> 0.4"},
      {:stream_data, "~> 0.4", only: [:test, :dev]},
      {:tzdata, "~> 1.0", only: [:test, :dev]},
      {:benchee, "~> 1.0", only: [:test, :dev], runtime: false},
      {:credo, "~> 1.4", only: [:test, :dev], runtime: false},
      {:dialyxir, "~> 1.0", only: [:test, :dev], runtime: false},
      {:ex_doc, "~> 0.20", only: [:test, :dev], runtime: false},
      {:nimble_parsec, "~> 1.0", only: [:test, :dev], runtime: false, override: true}
    ]
  end

  defp aliases do
    [
      bench: "run bench/bench_helper.exs",
      "test.setup": ["ecto.create", "ecto.migrate"],
      ci: [
        "format --check-formatted",
        "credo --strict",
        "test --raise",
        "dialyzer"
      ]
    ]
  end
end
