defmodule Oban.Integration.MigratingTest do
  use Oban.Case

  @moduletag :integration

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

  @base_version 20_300_000_000_000

  test "migrating up and down between versions" do
    for up <- 1..4 do
      Application.put_env(:oban, :up_version, up)

      assert :ok = Ecto.Migrator.up(Repo, @base_version + up, StepMigration)
    end

    assert table_exists?("oban_jobs")
    assert table_exists?("oban_beats")

    for down <- 3..1 do
      Application.put_env(:oban, :down_version, down)

      # Migrations happen in reverse, we need to invert the migration number
      version = @base_version + 4 - down

      assert :ok = Ecto.Migrator.down(Repo, version, StepMigration)
    end

    refute table_exists?("oban_jobs")
    refute table_exists?("oban_beats")
  after
    Repo.query("DELETE FROM schema_migrations WHERE version > #{@base_version}")
    Repo.query("DROP SCHEMA IF EXISTS migrating CASCADE")
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
end
