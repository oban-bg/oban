defmodule Oban.Migrations.Postgres.V15 do
  @moduledoc false

  use Ecto.Migration

  def up(%{prefix: prefix}) do
    create_if_not_exists index(:oban_jobs, [:scheduled_at, :id],
                           name: :oban_jobs_staging_idx,
                           where: "state IN ('scheduled', 'retryable')",
                           prefix: prefix
                         )
  end

  def down(%{prefix: prefix}) do
    drop_if_exists index(:oban_jobs, [:scheduled_at, :id],
                     name: :oban_jobs_staging_idx,
                     prefix: prefix
                   )
  end
end
