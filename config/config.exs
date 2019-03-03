use Mix.Config

config :oban, Oban.Test.Repo,
  pool: Ecto.Adapters.SQL.Sandbox,
  priv: "test/support/",
  url: System.get_env("DATABASE_URL") || "postgres://localhost:5432/oban_test"
