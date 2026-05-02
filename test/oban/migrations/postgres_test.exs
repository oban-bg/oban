defmodule Oban.Migrations.PostgresTest do
  use Oban.Case, async: true

  import Oban.Migrations.Postgres, only: [initial_version: 0, current_version: 0]

  alias Oban.Migrations.Postgres

  @moduletag :unboxed

  defmodule StepMigration do
    use Ecto.Migration

    def up do
      Oban.Migration.up(version: :persistent_term.get({__MODULE__, :up}), prefix: "migrating")
    end

    def down do
      Oban.Migration.down(version: :persistent_term.get({__MODULE__, :down}), prefix: "migrating")
    end
  end

  defmodule DefaultMigration do
    use Ecto.Migration

    def up do
      Oban.Migration.up(prefix: "migrating")
    end

    def down do
      Oban.Migration.down(prefix: "migrating")
    end
  end

  defmodule DefaultMigrationNoSchemaCreation do
    use Ecto.Migration

    def up do
      Oban.Migration.up(prefix: "migrating", create_schema: false)
    end

    def down do
      Oban.Migration.down(prefix: "migrating")
    end
  end

  @base_version 20_300_000_000_000

  test "verifying that any migrations have ran" do
    assert_raise RuntimeError, ~r/migrations have not been run/, fn ->
      start_supervised_oban!(repo: Repo, testing: :manual, prefix: "does_not_exist")
    end
  end

  test "verifying the database is migrated to the required version" do
    :persistent_term.put({StepMigration, :up}, current_version() - 1)

    assert :ok = Ecto.Migrator.up(UnboxedRepo, @base_version, StepMigration)

    assert_raise RuntimeError, ~r/migrations are outdated/, fn ->
      start_supervised_oban!(repo: UnboxedRepo, testing: :manual, prefix: "migrating")
    end
  after
    clear_migrated()
  end

  test "migrating up and down between specific versions" do
    for up <- initial_version()..current_version() do
      :persistent_term.put({StepMigration, :up}, up)

      assert :ok = Ecto.Migrator.up(UnboxedRepo, @base_version + up, StepMigration)
      assert migrated_version() == up
    end

    assert table_exists?("oban_jobs")
    assert table_exists?("oban_peers")
    assert migrated_version() == current_version()

    :persistent_term.put({StepMigration, :down}, 2)
    assert :ok = Ecto.Migrator.down(UnboxedRepo, @base_version + 2, StepMigration)

    assert table_exists?("oban_jobs")
    assert migrated_version() == 1

    :persistent_term.put({StepMigration, :down}, 1)
    assert :ok = Ecto.Migrator.down(UnboxedRepo, @base_version + 1, StepMigration)

    refute table_exists?("oban_jobs")
    refute table_exists?("oban_peers")
  after
    clear_migrated()
  end

  test "migrating up and down between default versions" do
    assert :ok = Ecto.Migrator.up(UnboxedRepo, @base_version, DefaultMigration)

    assert table_exists?("oban_jobs")
    assert migrated_version() == current_version()

    # Migrating once more to replicate multiple migrations that don't specify a version.
    assert :ok = Ecto.Migrator.up(UnboxedRepo, @base_version + 1, DefaultMigration)
    assert :ok = Ecto.Migrator.down(UnboxedRepo, @base_version + 1, DefaultMigration)

    refute table_exists?("oban_jobs")

    # Migrating once more to replicate multiple migrations that don't specify a version.
    assert :ok = Ecto.Migrator.down(UnboxedRepo, @base_version, DefaultMigration)
  after
    clear_migrated()
  end

  test "skipping schema creation when schema doesn't exist" do
    assert_raise Postgrex.Error, fn ->
      Ecto.Migrator.up(UnboxedRepo, @base_version, DefaultMigrationNoSchemaCreation)
    end

    refute table_exists?("oban_jobs")
    assert migrated_version() == 0
  after
    clear_migrated()
  end

  test "skipping schema creation when schema does exist" do
    UnboxedRepo.query!("CREATE SCHEMA IF NOT EXISTS migrating")

    assert :ok = Ecto.Migrator.up(UnboxedRepo, @base_version, DefaultMigrationNoSchemaCreation)

    assert table_exists?("oban_jobs")
    assert migrated_version() == current_version()
  after
    clear_migrated()
  end

  defp migrated_version do
    Postgres.migrated_version(repo: UnboxedRepo, prefix: "migrating")
  end

  defp table_exists?(table) do
    query = """
    SELECT EXISTS (
      SELECT 1
      FROM pg_tables
      WHERE schemaname = 'migrating'
      AND tablename = '#{table}'
    )
    """

    {:ok, %{rows: [[bool]]}} = UnboxedRepo.query(query)

    bool
  end

  defp clear_migrated do
    UnboxedRepo.query("DELETE FROM schema_migrations WHERE version >= #{@base_version}")
    UnboxedRepo.query("DROP SCHEMA IF EXISTS migrating CASCADE")
  end
end
