defmodule Oban.MixProject do
  use Mix.Project

  @version "1.1.0"

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
        flags: [:error_handling, :race_conditions, :underspecs]
      ],

      # Docs
      name: "Oban",
      docs: [
        main: "Oban",
        source_ref: "v#{@version}",
        source_url: "https://github.com/sorentwo/oban",
        extras: ["README.md", "CHANGELOG.md": [filename: "CHANGELOG.md", title: "CHANGELOG"]]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  def package do
    [
      maintainers: ["Parker Selbert"],
      licenses: ["Apache-2.0"],
      links: %{github: "https://github.com/sorentwo/oban"}
    ]
  end

  defp deps do
    [
      {:ecto_sql, "~> 3.1"},
      {:jason, "~> 1.1"},
      {:postgrex, "~> 0.14"},
      {:telemetry, "~> 0.4"},
      {:stream_data, "~> 0.4", only: [:test, :dev]},
      {:tzdata, "~> 1.0", only: [:test, :dev]},
      {:benchee, "~> 1.0", only: [:test, :dev], runtime: false},
      {:credo, "~> 1.0", only: [:test, :dev], runtime: false},
      {:dialyxir, "~> 0.5", only: [:test, :dev], runtime: false},
      {:ex_doc, "~> 0.20", only: [:test, :dev], runtime: false},
      {:nimble_parsec, "~> 0.5", only: [:test, :dev], runtime: false}
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
        "dialyzer --halt-exit-status"
      ]
    ]
  end
end
