# Running Oban with SQLite3

Oban ships with engines for PostgreSQL and [SQLite3][sqlite3]. Both engines support the same core
functionality for a single node. However, the Postgres engine is more advanced and designed to run
in a distributed environment.

Running with SQLite3 requires adding `ecto_sqlite3` to your app's dependencies and setting the
Oban engine to `Oban.Engines.Lite`:

```elixir
# In config/config.exs
config :my_app, Oban,
  engine: Oban.Engines.Lite,
  queues: [default: 10],
  repo: MyApp.Repo
```

> #### High Concurrency Systems {: .warning}
>
> SQLite3 may not be suitable for high-concurrency systems or for systems that need to handle
> large amounts of data. If you expect your background jobs to generate high loads, it would be
> better to use a more robust database solution that supports horizontal scalability, like
> Postgres.

[sqlite3]: https://www.sqlite.org/
