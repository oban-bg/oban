defmodule Oban.Migrations.V01 do
  @moduledoc false

  use Ecto.Migration

  def up(%{prefix: prefix, create_schema: create_schema}) do
    quoted_prefix = inspect(prefix)
    escaped_prefix = String.replace(prefix, "'", "\\'")

    if create_schema, do: execute("CREATE SCHEMA IF NOT EXISTS #{quoted_prefix}")

    execute """
    DO $$
    BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type
                   WHERE typname = 'oban_job_state'
                     AND typnamespace = '#{escaped_prefix}'::regnamespace::oid) THEN
        CREATE TYPE #{quoted_prefix}.oban_job_state AS ENUM (
          'available',
          'scheduled',
          'executing',
          'retryable',
          'completed',
          'discarded'
        );
      END IF;
    END$$;
    """

    create_if_not_exists table(:oban_jobs, primary_key: false, prefix: prefix) do
      add :id, :bigserial, primary_key: true
      add :state, :"#{quoted_prefix}.oban_job_state", null: false, default: "available"
      add :queue, :text, null: false, default: "default"
      add :worker, :text, null: false
      add :args, :map, null: false
      add :errors, {:array, :map}, null: false, default: []
      add :attempt, :integer, null: false, default: 0
      add :max_attempts, :integer, null: false, default: 20

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("timezone('UTC', now())")

      add :scheduled_at, :utc_datetime_usec,
        null: false,
        default: fragment("timezone('UTC', now())")

      add :attempted_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec
    end

    create_if_not_exists index(:oban_jobs, [:queue], prefix: prefix)
    create_if_not_exists index(:oban_jobs, [:state], prefix: prefix)
    create_if_not_exists index(:oban_jobs, [:scheduled_at], prefix: prefix)

    execute """
    CREATE OR REPLACE FUNCTION #{quoted_prefix}.oban_jobs_notify() RETURNS trigger AS $$
    DECLARE
      channel text;
      notice json;
    BEGIN
      IF (TG_OP = 'INSERT') THEN
        channel = '#{escaped_prefix}.oban_insert';
        notice = json_build_object('queue', NEW.queue, 'state', NEW.state);

        -- No point triggering for a job that isn't scheduled to run now
        IF NEW.scheduled_at IS NOT NULL AND NEW.scheduled_at > now() AT TIME ZONE 'utc' THEN
          RETURN null;
        END IF;
      ELSE
        channel = '#{escaped_prefix}.oban_update';
        notice = json_build_object('queue', NEW.queue, 'new_state', NEW.state, 'old_state', OLD.state);
      END IF;

      PERFORM pg_notify(channel, notice::text);

      RETURN NULL;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute "DROP TRIGGER IF EXISTS oban_notify ON #{quoted_prefix}.oban_jobs"

    execute """
    CREATE TRIGGER oban_notify
    AFTER INSERT OR UPDATE OF state ON #{quoted_prefix}.oban_jobs
    FOR EACH ROW EXECUTE PROCEDURE #{quoted_prefix}.oban_jobs_notify();
    """
  end

  def down(%{prefix: prefix}) do
    quoted_prefix = inspect(prefix)
    execute "DROP TRIGGER IF EXISTS oban_notify ON #{quoted_prefix}.oban_jobs"
    execute "DROP FUNCTION IF EXISTS #{quoted_prefix}.oban_jobs_notify()"

    drop_if_exists table(:oban_jobs, prefix: prefix)

    execute "DROP TYPE IF EXISTS #{quoted_prefix}.oban_job_state"
  end
end
