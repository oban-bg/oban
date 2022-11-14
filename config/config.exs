import Config

config :elixir, :time_zone_database, Tz.TimeZoneDatabase

config :logger, level: :warn

config :oban, Oban.Test.Repo,
  migration_lock: false,
  name: Oban.Test.Repo,
  pool: Ecto.Adapters.SQL.Sandbox,
  priv: "test/support/",
  url: System.get_env("DATABASE_URL") || "postgres://localhost:5432/oban_test"

config :oban,
  ecto_repos: [Oban.Test.Repo]
