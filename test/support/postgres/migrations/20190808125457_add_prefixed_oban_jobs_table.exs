defmodule Oban.Test.Repo.Migrations.AddPrefixedObanJobsTable do
  use Ecto.Migration

  def up do
    Oban.Migrations.up(prefix: "private")
  end

  def down do
    Oban.Migrations.down(prefix: "private", version: 1)
  end
end
