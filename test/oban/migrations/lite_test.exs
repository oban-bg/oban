defmodule Oban.Migrations.SQLiteTest do
  use Oban.Case, async: true

  defmodule MigrationRepo do
    @moduledoc false

    use Ecto.Repo, otp_app: :oban, adapter: Ecto.Adapters.SQLite3

    alias Oban.Test.LiteRepo

    def init(_, _) do
      {:ok, Keyword.put(LiteRepo.config(), :database, "priv/migration.db")}
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

  test "migrating a sqlite database" do
    start_supervised!(MigrationRepo)

    MigrationRepo.__adapter__().storage_up(MigrationRepo.config())

    assert :ok = Ecto.Migrator.up(MigrationRepo, 1, Migration)
    assert table_exists?()

    assert :ok = Ecto.Migrator.down(MigrationRepo, 1, Migration)
    refute table_exists?()
  end

  defp table_exists? do
    query = """
    SELECT EXISTS (
      SELECT 1
      FROM sqlite_master
      WHERE type='table'
        AND name='oban_jobs'
    )
    """

    {:ok, %{rows: [[exists]]}} = MigrationRepo.query(query)

    exists != 0
  end
end
