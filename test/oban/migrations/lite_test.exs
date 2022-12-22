defmodule Oban.Migrations.SQLiteTest do
  use Oban.Case, async: true

  alias Oban.Test.LiteRepo

  @moduletag :lite

  setup_all do
    conf = Keyword.put(LiteRepo.config(), :database, "priv/migrations.db")

    LiteRepo.__adapter__().storage_down(conf)
    LiteRepo.__adapter__().storage_up(conf)

    on_exit(fn -> LiteRepo.__adapter__().storage_down(conf) end)

    :ok
  end

  defmodule Migration do
    use Ecto.Migration

    def up do
      Oban.Migration.up()
    end

    def down do
      Oban.Migration.down()
    end
  end

  @base_version 20_300_000_000_000

  test "migrating a sqlite database" do
    assert :ok = Ecto.Migrator.up(LiteRepo, @base_version + 1, Migration)
    assert table_exists?()

    assert :ok = Ecto.Migrator.down(LiteRepo, @base_version + 1, Migration)
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

    {:ok, %{rows: [[exists]]}} = LiteRepo.query(query)

    exists != 0
  end
end
