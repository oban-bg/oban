defmodule Oban.Migrations.Postgres.V13 do
  @moduledoc false

  use Ecto.Migration

  def change do
    create index(:oban_jobs, [:state, :cancelled_at])
    create index(:oban_jobs, [:state, :discarded_at])
  end
end
