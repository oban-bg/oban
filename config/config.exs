import Config

config :elixir, :time_zone_database, Tz.TimeZoneDatabase

config :logger, level: :warning

config :oban, Oban.Backoff, retry_mult: 1

config :oban, Oban.Test.Repo,
  migration_lock: false,
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2,
  priv: "test/support/postgres",
  show_sensitive_data_on_connection_error: true,
  stacktrace: true,
  url: System.get_env("POSTGRES_URL") || "postgres://localhost:5432/oban_test"

config :oban, Oban.Test.LiteRepo,
  database: "priv/oban.db",
  priv: "test/support/sqlite",
  stacktrace: true,
  temp_store: :memory

config :oban, Oban.Test.DolphinRepo,
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2,
  priv: "test/support/myxql",
  show_sensitive_data_on_connection_error: true,
  stacktrace: true,
  url: System.get_env("MYSQL_URL") || "mysql://root@localhost:3306/oban_test"

config :oban,
  ecto_repos: [Oban.Test.Repo, Oban.Test.LiteRepo, Oban.Test.DolphinRepo]
