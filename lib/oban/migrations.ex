defmodule Oban.Migrations do
  @moduledoc false

  use Ecto.Migration

  @initial_version 1
  @current_version 2

  def up(version \\ @current_version) do
    change(get_current()..version, :up)
  end

  def down(version \\ @current_version) do
    change(get_current()..version, :down)
  end

  defp change(range, direction) do
    for index <- range do
      [__MODULE__, "V#{index}"]
      |> Module.safe_concat()
      |> apply(direction, [])
    end
  end

  defp get_current do
    result =
      repo().query("""
      SELECT description
      FROM pg_class
      LEFT JOIN pg_description ON pg_description.objoid = pg_class.oid
      WHERE relname = 'oban_jobs'
      """)

    case result do
      {:ok, %{rows: [[version]]}} when is_binary(version) -> String.to_integer(version)
      _ -> @initial_version
    end
  end

  defmodule V1 do
    @moduledoc false

    use Ecto.Migration

    defmacrop now do
      quote do
        fragment("timezone('UTC', now())")
      end
    end

    def up do
      execute """
      DO $$
      BEGIN
        IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'oban_job_state') THEN
          CREATE TYPE oban_job_state AS ENUM (
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

      create_if_not_exists index(:oban_jobs, [:queue])
      create_if_not_exists index(:oban_jobs, [:state])
      create_if_not_exists index(:oban_jobs, [:scheduled_at])

      execute """
      CREATE OR REPLACE FUNCTION oban_jobs_notify() RETURNS trigger AS $$
      DECLARE
        channel text;
        notice json;
      BEGIN
        IF (TG_OP = 'INSERT') THEN
          channel = 'oban_insert';
          notice = json_build_object('queue', NEW.queue, 'state', NEW.state);

          -- No point triggering for a job that isn't scheduled to run now
          IF NEW.scheduled_at IS NOT NULL AND NEW.scheduled_at > now() AT TIME ZONE 'utc' THEN
            RETURN null;
          END IF;
        ELSE
          channel = 'oban_update';
          notice = json_build_object('queue', NEW.queue, 'new_state', NEW.state, 'old_state', OLD.state);
        END IF;

        PERFORM pg_notify(channel, notice::text);

        RETURN NULL;
      END;
      $$ LANGUAGE plpgsql;
      """

      execute "DROP TRIGGER IF EXISTS oban_notify ON oban_jobs"

      execute """
      CREATE TRIGGER oban_notify
      AFTER INSERT OR UPDATE ON oban_jobs
      FOR EACH ROW EXECUTE PROCEDURE oban_jobs_notify();
      """

      execute "COMMENT ON TABLE oban_jobs IS '1'"
    end

    def down do
      execute "DROP TRIGGER oban_notify ON oban_jobs"
      execute "DROP FUNCTION oban_jobs_notify()"

      drop_if_exists table("oban_jobs")

      execute "DROP TYPE IF EXISTS oban_job_state"
    end
  end

  defmodule V2 do
    @moduledoc false

    use Ecto.Migration

    def up do
      # We only need the scheduled_at index for scheduled and available jobs
      drop_if_exists index(:oban_jobs, [:scheduled_at])

      create index(:oban_jobs, [:scheduled_at],
               where: "state in ('available'::oban_job_state, 'scheduled'::oban_job_state)"
             )

      create constraint(:oban_jobs, :worker_length,
               check: "char_length(worker) > 0 AND char_length(worker) < 128"
             )

      create constraint(:oban_jobs, :queue_length,
               check: "char_length(queue) > 0 AND char_length(queue) < 128"
             )

      execute """
      CREATE OR REPLACE FUNCTION oban_wrap_id(value bigint) RETURNS int AS $$
      BEGIN
        RETURN (CASE WHEN value > 2147483647 THEN mod(value, 2147483647) ELSE value END)::int;
      END;
      $$ LANGUAGE plpgsql IMMUTABLE;
      """

      execute "COMMENT ON TABLE oban_jobs IS '2'"
    end

    def down do
      drop_if_exists constraint(:oban_jobs, :queue_length)
      drop_if_exists constraint(:oban_jobs, :worker_length)

      drop_if_exists index(:oban_jobs, [:scheduled_at])
      create index(:oban_jobs, [:scheduled_at])

      execute("DROP FUNCTION oban_wrap_id(value bigint)")

      execute "COMMENT ON TABLE oban_jobs IS '1'"
    end
  end
end
