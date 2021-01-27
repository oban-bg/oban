defmodule Oban.MigrationsTest do
  use Oban.Case, async: true

  import Oban.Migrations, only: [initial_version: 0, current_version: 0, migrated_version: 2]

  @arbitrary_checks 20

  defmodule StepMigration do
    use Ecto.Migration

    def up do
      Oban.Migrations.up(version: up_version(), prefix: "migrating")
    end

    def down do
      Oban.Migrations.down(version: down_version(), prefix: "migrating")
    end

    defp up_version do
      Application.get_env(:oban, :up_version)
    end

    def down_version do
      Application.get_env(:oban, :down_version)
    end
  end

  defmodule DefaultMigration do
    use Ecto.Migration

    def up do
      Oban.Migrations.up(prefix: "migrating")
    end

    def down do
      Oban.Migrations.down(prefix: "migrating")
    end
  end

  @base_version 20_300_000_000_000

  test "migrating up and down between specific versions" do
    for up <- initial_version()..current_version() do
      Application.put_env(:oban, :up_version, up)

      assert :ok = Ecto.Migrator.up(Repo, @base_version + up, StepMigration)
      assert migrated_version() == up
    end

    assert table_exists?("oban_jobs")
    assert table_exists?("oban_beats")
    assert migrated_version() == current_version()

    Application.put_env(:oban, :down_version, 2)
    assert :ok = Ecto.Migrator.down(Repo, @base_version + 2, StepMigration)

    assert table_exists?("oban_jobs")
    refute table_exists?("oban_beats")
    assert migrated_version() == 1

    Application.put_env(:oban, :down_version, 1)
    assert :ok = Ecto.Migrator.down(Repo, @base_version + 1, StepMigration)

    refute table_exists?("oban_jobs")
    refute table_exists?("oban_beats")
  after
    clear_migrated()
  end

  test "migrating up and down between default versions" do
    assert :ok = Ecto.Migrator.up(Repo, @base_version, DefaultMigration)

    assert table_exists?("oban_jobs")
    assert table_exists?("oban_beats")
    assert migrated_version() == current_version()

    # Migrating once more to replicate multiple migrations that don't specify a version.
    assert :ok = Ecto.Migrator.up(Repo, @base_version + 1, DefaultMigration)

    assert :ok = Ecto.Migrator.down(Repo, @base_version + 1, DefaultMigration)

    refute table_exists?("oban_jobs")
    refute table_exists?("oban_beats")

    # Migrating once more to replicate multiple migrations that don't specify a version.
    assert :ok = Ecto.Migrator.down(Repo, @base_version, DefaultMigration)
  after
    clear_migrated()
  end

  test "migrating up and down between arbitrary versions" do
    ups = 2..current_version()
    dns = 1..(current_version() - 1)

    ups
    |> Enum.zip(dns)
    |> Enum.shuffle()
    |> Enum.take(@arbitrary_checks)
    |> Enum.each(fn {up, down} ->
      Application.put_env(:oban, :up_version, up)
      Application.put_env(:oban, :down_version, down)

      assert :ok = Ecto.Migrator.up(Repo, @base_version, StepMigration)
      assert :ok = Ecto.Migrator.down(Repo, @base_version, StepMigration)

      clear_migrated()
    end)
  end

  defp migrated_version do
    migrated_version(Repo, "migrating")
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

    {:ok, %{rows: [[bool]]}} = Repo.query(query)

    bool
  end

  defp clear_migrated do
    Repo.query("DELETE FROM schema_migrations WHERE version >= #{@base_version}")
    Repo.query("DROP SCHEMA IF EXISTS migrating CASCADE")
  end
end
