use Mix.Config

config :oban, Oban.Test.Repo,
  pool: Ecto.Adapters.SQL.Sandbox,
  priv: "test/support/",
  url: "postgres://localhost:5432/oban_test"
