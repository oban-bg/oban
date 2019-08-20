defmodule Oban.Test.Repo.Migrations.AddObanJobsTable do
  use Ecto.Migration

  defdelegate up, to: Oban.Migrations

  def down do
    Oban.Migrations.down(version: 1)
  end
end
