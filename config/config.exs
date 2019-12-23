use Mix.Config

config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

config :oban, Oban.Test.Repo,
  priv: "test/support/",
  url: System.get_env("DATABASE_URL") || "postgres://localhost:5432/oban_test"

config :oban,
  ecto_repos: [Oban.Test.Repo]
