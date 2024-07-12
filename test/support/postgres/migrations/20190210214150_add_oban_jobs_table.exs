defmodule Oban.Test.Repo.Postgres.Migrations.AddObanJobsTable do
  use Ecto.Migration

  def up do
    Oban.Migrations.up(unlogged: false)
    Oban.Migrations.up(prefix: "private", unlogged: false)
  end

  def down do
    Oban.Migrations.down(prefix: "private", version: 1)
    Oban.Migrations.down(version: 1)
  end
end
