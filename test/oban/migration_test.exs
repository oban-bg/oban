defmodule Oban.MigrationTest do
  use ExUnit.Case, async: true

  defmodule CustomAdapter do
  end

  defmodule CustomMigrator do
    def current_version, do: 42
    def migrated_version(_opts), do: 42
  end

  defmodule CustomRepo do
    def __adapter__, do: CustomAdapter
    def config, do: [migrator: CustomMigrator]
  end

  test "uses the configured custom migrator when verifying migrations" do
    assert :ok = Oban.Migration.verify_migrated!(repo: CustomRepo)
  end
end
