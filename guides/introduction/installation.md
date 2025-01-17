# Installation

Oban may be installed and configured via [igniter](https://hex.pm/packages/igniter) with a single command:

```bash
mix igniter.install oban
```

That will add the latest version of `oban` to your dependencies before running the installer.
Installation will use the application's default Ecto repo, select the corresponding engine, and
set the pubsub notifier accordingly.

Use the `--repo` flag to specify an alternate repo manually:

```bash
mix igniter.install oban --repo MyApp.LiteRepo
```

## Semi-Automatic Installation

It's possible to use the `oban.install` task without `igniter` available. First, add `oban` to
your deps in `mix.exs`:

```elixir
{:oban, "~> 2.19"}
```

Run `mix deps.get` to fetch `oban`, then run the install task:

```bash
mix oban.install
```

That will automate all of the manual steps listed below!

## Manual Installation

Oban is published on [Hex](https://hex.pm/packages/oban). Add it to your list of deps in
`mix.exs`:

```elixir
{:oban, "~> 2.19"}
```

You'll optionally need to include [Postgrex][postgrex] for Postgres, [EctoSQLite3][ecto_sqlite3]
for SQLite3, or [MyXQL][myxql] for use with MySQL. Then run `mix deps.get` to install Oban and its
dependencies.

After the packages are installed you must create a database migration to add the `oban_jobs` table
to your database:

```bash
mix ecto.gen.migration add_oban_jobs_table
```

Open the generated migration in your editor and call the `up` and `down` functions on
`Oban.Migration`:

```elixir
defmodule MyApp.Repo.Migrations.AddObanJobsTable do
  use Ecto.Migration

  def up do
    Oban.Migration.up(version: 12)
  end

  # We specify `version: 1` in `down`, ensuring that we'll roll all the way back down if
  # necessary, regardless of which version we've migrated `up` to.
  def down do
    Oban.Migration.down(version: 1)
  end
end
```

This will run all of Oban's versioned migrations for your database. Migrations between versions
are idempotent and rarely change after a release. As new versions are released you may need to run
additional migrations.

Now, run the migration to create the table:

```bash
mix ecto.migrate
```

Before you can run an Oban instance you must provide some base configuration:

<!-- tabs-open -->

### Postgres

Running with Postgres requires using the `Oban.Engines.Basic` engine:

```elixir
# config/config.exs
config :my_app, Oban,
  engine: Oban.Engines.Basic,
  queues: [default: 10],
  repo: MyApp.Repo
```

### SQLite3

Running with SQLite3 requires using the `Oban.Engines.Lite` engine:
 
```elixir
# config/config.exs
config :my_app, Oban,
  engine: Oban.Engines.Lite,
  queues: [default: 10],
  repo: MyApp.Repo
```

### MySQL

Running with MySQL requires using the `Oban.Engines.Dolphin` engine:

```elixir
# config/config.exs
config :my_app, Oban,
  engine: Oban.Engines.Dolphin,
  queues: [default: 10],
  repo: MyApp.Repo
```

<!-- tabs-close -->

To prevent Oban from running jobs and plugins during test runs, enable `:testing` mode in
`test.exs`:

```elixir
# config/test.exs
config :my_app, Oban, testing: :manual
```

Oban instances are isolated supervision trees and must be included in your application's
supervisor to run. Use the application configuration you've just set and include Oban in the list
of supervised children:

```elixir
# lib/my_app/application.ex
def start(_type, _args) do
  children = [
    MyApp.Repo,
    {Oban, Application.fetch_env!(:my_app, Oban)}
  ]

  Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)
end
```

Finally, verify that Oban is configured and running properly. Within a new `iex -S mix` session:

```elixir
iex(1)> Oban.config()
#=> %Oban.Config{repo: MyApp.Repo}
```

You're all set! Add the [Oban Web][web] dashboard for monitoring, get started creating jobs and
configuring queues in [Usage][use], or head to the [testing guide][test] to learn how to test with
Oban.

[use]: Oban.html#Usage
[web]: https://github.com/oban-bg/oban_web
[test]: testing.md
[postgrex]: https://hex.pm/packages/postgrex
[ecto_sqlite3]: https://hex.pm/packages/ecto_sqlite3
[myxql]: https://hex.pm/packages/myxql
