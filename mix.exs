defmodule Oban.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :oban,
      version: "0.1.0",
      elixir: "~> 1.8",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),

      # Hex
      package: package(),
      description: """
      Smooth job queue powered by PostgreSQL and GenStage
      """,

      # Dialyzer
      dialyzer: [
        plt_add_apps: [:eex, :ex_unit, :mix],
        flags: [:error_handling, :race_conditions, :underspecs]
      ],

      # Docs
      name: "Oban",
      docs: [
        main: "Oban",
        source_ref: "v#{@version}",
        source_url: "https://github.com/sorentwo/oban",
        extras: ["README.md", "CHANGELOG.md"]
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
      licenses: ["MIT"],
      links: %{github: "https://github.com/sorentwo/oban"}
    ]
  end

  defp deps do
    [
      {:ecto_sql, "~> 3.0"},
      {:gen_stage, "~> 0.14"},
      {:jason, "~> 1.1"},
      {:postgrex, "~> 0.14"},
      {:telemetry, "~> 0.3"},
      {:propcheck, "~> 1.0", only: [:test]},
      {:credo, "~> 1.0", only: [:dev], runtime: false},
      {:dialyxir, "~> 0.5", only: [:dev], runtime: false}
    ]
  end
end
