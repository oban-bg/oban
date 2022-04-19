# Installation

Oban is published on [Hex](https://hex.pm/packages/oban). Add it to your list of
dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:oban, "~> 2.12"}
  ]
end
```

Then run `mix deps.get` to install Oban and its dependencies, including
[Ecto][ecto], [Jason][jason] and [Postgrex][postgrex].

After the packages are installed you must create a database migration to
add the `oban_jobs` table to your database:

```bash
mix ecto.gen.migration add_oban_jobs_table
```

Open the generated migration in your editor and call the `up` and `down`
functions on `Oban.Migrations`:

```elixir
defmodule MyApp.Repo.Migrations.AddObanJobsTable do
  use Ecto.Migration

  def up do
    Oban.Migrations.up(version: 11)
  end

  # We specify `version: 1` in `down`, ensuring that we'll roll all the way back down if
  # necessary, regardless of which version we've migrated `up` to.
  def down do
    Oban.Migrations.down(version: 1)
  end
end
```

This will run all of Oban's versioned migrations for your database. Migrations
between versions are idempotent and will _never_ change after a release. As new
versions are released you may need to run additional migrations.

Now, run the migration to create the table:

```bash
mix ecto.migrate
```

Next see [Usage](Oban.html#Usage) for how to integrate Oban into your application and
start defining jobs!

[ecto]: https://hex.pm/packages/ecto
[jason]: https://hex.pm/packages/jason
[postgrex]: https://hex.pm/packages/postgrex
