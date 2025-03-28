defmodule Oban.Migrations.Postgres.V13 do
  @moduledoc false

  use Ecto.Migration

  def up(%{prefix: prefix}) do
    create_if_not_exists index(:oban_jobs, [:state, :cancelled_at], prefix: prefix)
    create_if_not_exists index(:oban_jobs, [:state, :discarded_at], prefix: prefix)
  end

  def down(%{prefix: prefix}) do
    drop_if_exists index(:oban_jobs, [:state, :discarded_at], prefix: prefix)
    drop_if_exists index(:oban_jobs, [:state, :cancelled_at], prefix: prefix)
  end
end
