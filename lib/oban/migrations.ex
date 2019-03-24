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
    CREATE TYPE oban_job_state AS ENUM ('available', 'executing', 'completed', 'discarded')
    """

    create_if_not_exists table(:oban_jobs) do
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

    execute """
    CREATE FUNCTION oban_jobs_notify()
      RETURNS trigger AS $$
    DECLARE
    BEGIN
      PERFORM pg_notify('oban_insert', NEW.queue);
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql
    """

    execute """
    CREATE TRIGGER notify_inserted
    AFTER INSERT ON oban_jobs
    FOR EACH ROW
    EXECUTE PROCEDURE oban_jobs_notify();
    """
  end

  def down do
    execute("DROP TRIGGER notify_inserted ON oban_jobs")
    execute("DROP FUNCTION oban_jobs_notify()")

    drop_if_exists table("oban_jobs")

    execute("DROP TYPE IF EXISTS oban_job_state")
  end
end
