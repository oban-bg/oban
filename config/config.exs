import Config

config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

config :logger, level: :warn

config :oban, Oban.Test.Repo,
  name: Oban.Test.Repo,
  priv: "test/support/",
  url: System.get_env("DATABASE_URL") || "postgres://localhost:5432/oban_test",
  pool: Ecto.Adapters.SQL.Sandbox

config :oban,
  ecto_repos: [Oban.Test.Repo]
