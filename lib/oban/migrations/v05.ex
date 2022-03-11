defmodule Oban.Migrations.V05 do
  @moduledoc false

  use Ecto.Migration

  def up(%{prefix: prefix}) do
    drop_if_exists index(:oban_jobs, [:scheduled_at], prefix: prefix)
    drop_if_exists index(:oban_jobs, [:queue], prefix: prefix)
    drop_if_exists index(:oban_jobs, [:state], prefix: prefix)

    create_if_not_exists index(:oban_jobs, [:queue, :state, :scheduled_at, :id], prefix: prefix)
  end

  def down(%{prefix: prefix, quoted_prefix: quoted}) do
    drop_if_exists index(:oban_jobs, [:queue, :state, :scheduled_at, :id], prefix: prefix)

    state = "#{quoted}.oban_job_state"

    create_if_not_exists index(:oban_jobs, [:queue], prefix: prefix)
    create_if_not_exists index(:oban_jobs, [:state], prefix: prefix)

    create index(:oban_jobs, [:scheduled_at],
             where: "state in ('available'::#{state}, 'scheduled'::#{state})",
             prefix: prefix
           )
  end
end
