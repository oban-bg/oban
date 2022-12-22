defmodule Oban.Test.Repo.SQLite.Migrations.AddObanJobsTable do
  use Ecto.Migration

  defdelegate up, to: Oban.Migration
  defdelegate down, to: Oban.Migration
end
