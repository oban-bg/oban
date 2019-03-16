defmodule Oban.Migrations do
  @moduledoc false

  use Ecto.Migration

  defmacrop now do
    quote do
      fragment("timezone('UTC', now())")
    end
  end

  def up do
    execute """
    create type oban_job_state as enum ('available', 'executing', 'completed', 'discarded')
    """

    create table(:oban_jobs) do
      add :state, :oban_job_state, null: false, default: "available"
      add :queue, :text, null: false, default: "default"
      add :worker, :text, null: false
      add :args, :map, null: false
      add :errors, {:array, :map}, null: false, default: []
      add :attempt, :integer, null: false, default: 0
      add :max_attempts, :integer, null: false, default: 20

      add :inserted_at, :utc_datetime_usec, null: false, default: now()
      add :scheduled_at, :utc_datetime_usec, null: false, default: now()
      add :attempted_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec
    end

    create index(:oban_jobs, [:state, :queue])
    create index(:oban_jobs, [:scheduled_at])
  end

  def down do
    drop_if_exists table("oban_jobs")

    execute("drop type if exists oban_job_state")
  end
end
