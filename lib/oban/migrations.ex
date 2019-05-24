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
    CREATE TYPE oban_job_state AS ENUM ('available', 'scheduled', 'executing', 'retryable', 'completed', 'discarded')
    """

    create_if_not_exists table(:oban_jobs, primary_key: false) do
      add :id, :bigserial, primary_key: true
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

    create index(:oban_jobs, [:queue])
    create index(:oban_jobs, [:state])
    create index(:oban_jobs, [:scheduled_at])

    execute """
    CREATE OR REPLACE FUNCTION oban_jobs_notify() RETURNS trigger AS $$
    DECLARE
      channel text;
      notice json;
    BEGIN
      IF (TG_OP = 'INSERT') THEN
        channel = 'oban_insert';
        notice = json_build_object('queue', NEW.queue, 'state', NEW.state);
      ELSE
        channel = 'oban_update';
        notice = json_build_object('queue', NEW.queue, 'new_state', NEW.state, 'old_state', OLD.state);
      END IF;

      PERFORM pg_notify(channel, notice::text);

      RETURN NULL;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER oban_notify
    AFTER INSERT OR UPDATE ON oban_jobs
    FOR EACH ROW EXECUTE PROCEDURE oban_jobs_notify();
    """
  end

  def down do
    execute("DROP TRIGGER oban_notify ON oban_jobs")
    execute("DROP FUNCTION oban_jobs_notify()")

    drop_if_exists table("oban_jobs")

    execute("DROP TYPE IF EXISTS oban_job_state")
  end
end
