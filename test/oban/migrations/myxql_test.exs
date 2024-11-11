defmodule Oban.Migrations.MyXQLTest do
  use Oban.Case, async: true

  defmodule MigrationRepo do
    @moduledoc false

    use Ecto.Repo, otp_app: :oban, adapter: Ecto.Adapters.MyXQL

    alias Oban.Test.DolphinRepo

    def init(_, _) do
      {:ok, Keyword.put(DolphinRepo.config(), :database, "oban_migrations")}
    end
  end

  @moduletag :lite

  defmodule Migration do
    use Ecto.Migration

    def up do
      Oban.Migration.up()
    end

    def down do
      Oban.Migration.down()
    end
  end

  test "migrating a mysql database" do
    MigrationRepo.__adapter__().storage_up(MigrationRepo.config())

    start_supervised!(MigrationRepo)

    assert :ok = Ecto.Migrator.up(MigrationRepo, 1, Migration)
    assert table_exists?("oban_jobs")
    assert table_exists?("oban_peers")

    assert :ok = Ecto.Migrator.down(MigrationRepo, 1, Migration)
    refute table_exists?("oban_jobs")
    refute table_exists?("oban_peers")
  after
    MigrationRepo.__adapter__().storage_down(MigrationRepo.config())
  end

  defp table_exists?(name) do
    query = """
    SELECT EXISTS (
      SELECT 1
      FROM information_schema.TABLES
      WHERE TABLE_SCHEMA = 'oban_migrations'
      AND TABLE_NAME = '#{name}'
    )
    """

    {:ok, %{rows: [[exists]]}} = MigrationRepo.query(query)

    exists != 0
  end
end
