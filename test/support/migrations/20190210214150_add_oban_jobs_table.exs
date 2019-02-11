defmodule Oban.Test.Repo.Migrations.AddObanJobsTable do
  use Ecto.Migration

  defdelegate up, to: Oban.Migrations
  defdelegate down, to: Oban.Migrations
end
