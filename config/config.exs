import Config

config :elixir, :time_zone_database, Tz.TimeZoneDatabase

config :logger, level: :warning

config :oban, Oban.Test.Repo,
  migration_lock: false,
  name: Oban.Test.Repo,
  pool: Ecto.Adapters.SQL.Sandbox,
  priv: "test/support/postgres",
  url: System.get_env("DATABASE_URL") || "postgres://localhost:5432/oban_test"

config :oban, Oban.Test.LiteRepo,
  database: "priv/oban.db",
  priv: "test/support/sqlite",
  temp_store: :memory

config :oban,
  ecto_repos: [Oban.Test.Repo, Oban.Test.LiteRepo]
