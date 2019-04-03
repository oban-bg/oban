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
      aliases: aliases(),

      # Hex
      package: package(),
      description: """
      Smooth asynchronous job execution powered by PostgreSQL
      """,

      # Dialyzer
      dialyzer: [
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
      {:ecto_sql, "~> 3.1"},
      {:jason, "~> 1.1"},
      {:postgrex, "~> 0.14"},
      {:telemetry, "~> 0.4"},
      {:propcheck, "~> 1.0", only: [:test]},
      {:credo, "~> 1.0", only: [:test, :dev], runtime: false},
      {:dialyxir, "~> 0.5", only: [:test, :dev], runtime: false},
      {:ex_doc, "~> 0.20", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [ci: ["format --check-formatted", "credo --strict", "test", "dialyzer --halt-exit-status"]]
  end
end
