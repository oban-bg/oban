defmodule Oban.Migrations do
  @moduledoc """
  Migrations create and modify the database tables Oban needs to funtion.

  ## Usage

  To use migrations in your application you'll need to generate an `Ecto.Migration` that wraps
  calls to `Oban.Migrations`:

  ```bash
  mix ecto.gen.migration add_oban
  ```

  Open the generated migration in your editor and call the `up` and `down` functions on
  `Oban.Migrations`:

  ```elixir
  defmodule MyApp.Repo.Migrations.AddOban do
    use Ecto.Migration

    def up, do: Oban.Migrations.up()

    def down, do: Oban.Migrations.down()
  end
  ```

  This will run all of Oban's versioned migrations for your database. Migrations between versions
  are idempotent. As new versions are released you may need to run additional migrations.

  Now, run the migration to create the table:

  ```bash
  mix ecto.migrate
  ```

  ## Isolation with Prefixes

  Oban supports namespacing through PostgreSQL schemas, also called "prefixes" in Ecto. With
  prefixes your jobs table can reside outside of your primary schema (usually public) and you can
  have multiple separate job tables.

  To use a prefix you first have to specify it within your migration:

  ```elixir
  defmodule MyApp.Repo.Migrations.AddPrefixedObanJobsTable do
    use Ecto.Migration

    def up, do: Oban.Migrations.up(prefix: "private")

    def down, do: Oban.Migrations.down(prefix: "private")
  end
  ```

  The migration will create the "private" schema and all tables, functions and triggers within
  that schema. With the database migrated you'll then specify the prefix in your configuration:

  ```elixir
  config :my_app, Oban,
    prefix: "private",
    ...
  ```
  """

  use Ecto.Migration

  alias Oban.Repo

  @initial_version 1
  @current_version 10
  @default_prefix "public"

  @doc """
  Run the `up` changes for all migrations between the initial version and the current version.

  ## Example

  Run all migrations up to the current version:

      Oban.Migrations.up()

  Run migrations up to a specified version:

      Oban.Migrations.up(version: 2)

  Run migrations in an alternate prefix:

      Oban.Migrations.up(prefix: "payments")
  """
  def up(opts \\ []) when is_list(opts) do
    prefix = Keyword.get(opts, :prefix, @default_prefix)
    version = Keyword.get(opts, :version, @current_version)
    initial = migrated_version(repo(), prefix)

    cond do
      initial == 0 -> change(prefix, @initial_version..version, :up)
      initial < version -> change(prefix, (initial + 1)..version, :up)
      true -> :ok
    end
  end

  @doc """
  Run the `down` changes for all migrations between the current version and the initial version.

  ## Example

  Run all migrations from current version down to the first:

      Oban.Migrations.down()

  Run migrations down to a specified version:

      Oban.Migrations.down(version: 5)

  Run migrations in an alternate prefix:

      Oban.Migrations.down(prefix: "payments")
  """
  def down(opts \\ []) when is_list(opts) do
    prefix = Keyword.get(opts, :prefix, @default_prefix)
    version = Keyword.get(opts, :version, @initial_version)
    initial = max(migrated_version(repo(), prefix), @initial_version)

    if initial >= version do
      change(prefix, initial..version, :down)
    end
  end

  @doc false
  def initial_version, do: @initial_version

  @doc false
  def current_version, do: @current_version

  @doc false
  def migrated_version(repo, prefix) do
    query = """
    SELECT description
    FROM pg_class
    LEFT JOIN pg_description ON pg_description.objoid = pg_class.oid
    LEFT JOIN pg_namespace ON pg_namespace.oid = pg_class.relnamespace
    WHERE pg_class.relname = 'oban_jobs'
    AND pg_namespace.nspname = '#{prefix}'
    """

    case Repo.query(%{repo: repo, prefix: prefix}, query) do
      {:ok, %{rows: [[version]]}} when is_binary(version) -> String.to_integer(version)
      _ -> 0
    end
  end

  defp change(prefix, range, direction) do
    for index <- range do
      pad_idx = String.pad_leading(to_string(index), 2, "0")

      [__MODULE__, "V#{pad_idx}"]
      |> Module.concat()
      |> apply(direction, [prefix])
    end

    case direction do
      :up -> record_version(prefix, Enum.max(range))
      :down -> record_version(prefix, Enum.min(range) - 1)
    end
  end

  defp record_version(_prefix, 0), do: :ok

  defp record_version(prefix, version) do
    execute "COMMENT ON TABLE #{prefix}.oban_jobs IS '#{version}'"
  end
end
