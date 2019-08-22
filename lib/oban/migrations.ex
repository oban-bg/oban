defmodule Oban.Migrations do
  @moduledoc false

  use Ecto.Migration

  @initial_version 1
  @current_version 4

  @default_opts %{prefix: "public", version: @current_version}

  def up(opts \\ []) when is_list(opts) do
    opts
    |> merge_defaults()
    |> change(:up)
  end

  def down(opts \\ []) when is_list(opts) do
    opts
    |> merge_defaults()
    |> change(:down)
  end

  defp merge_defaults(opts) do
    opts = Map.merge(@default_opts, Map.new(opts))

    Map.put(opts, :range, get_current(opts.prefix)..opts.version)
  end

  defp get_current(prefix) do
    result =
      repo().query("""
      SELECT description
      FROM pg_class
      LEFT JOIN pg_description ON pg_description.objoid = pg_class.oid
      LEFT JOIN pg_namespace ON pg_namespace.oid = pg_class.relnamespace
      WHERE pg_class.relname = 'oban_jobs' AND pg_namespace.nspname = '#{prefix}'
      """)

    case result do
      {:ok, %{rows: [[version]]}} when is_binary(version) -> String.to_integer(version)
      _ -> @initial_version
    end
  end

  defp change(%{prefix: prefix, range: range}, direction) do
    for index <- range do
      [__MODULE__, "V#{index}"]
      |> Module.safe_concat()
      |> apply(direction, [prefix])
    end
  end

  defmodule Macros do
    @moduledoc false

    defmacro now do
      quote do
        fragment("timezone('UTC', now())")
      end
    end
  end

  defmodule V1 do
    @moduledoc false

    use Ecto.Migration

    import Oban.Migrations.Macros

    def up(prefix) do
      execute "CREATE SCHEMA IF NOT EXISTS #{prefix}"

      execute """
      DO $$
      BEGIN
      IF NOT EXISTS (SELECT 1 FROM pg_type
                     WHERE typname = 'oban_job_state'
                       AND typnamespace = '#{prefix}'::regnamespace::oid) THEN
          CREATE TYPE #{prefix}.oban_job_state AS ENUM (
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
        add :state, :"#{prefix}.oban_job_state", null: false, default: "available"
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

      create_if_not_exists index(:oban_jobs, [:queue], prefix: prefix)
      create_if_not_exists index(:oban_jobs, [:state], prefix: prefix)
      create_if_not_exists index(:oban_jobs, [:scheduled_at], prefix: prefix)

      execute """
      CREATE OR REPLACE FUNCTION #{prefix}.oban_jobs_notify() RETURNS trigger AS $$
      DECLARE
        channel text;
        notice json;
      BEGIN
        IF (TG_OP = 'INSERT') THEN
          channel = '#{prefix}.oban_insert';
          notice = json_build_object('queue', NEW.queue, 'state', NEW.state);

          -- No point triggering for a job that isn't scheduled to run now
          IF NEW.scheduled_at IS NOT NULL AND NEW.scheduled_at > now() AT TIME ZONE 'utc' THEN
            RETURN null;
          END IF;
        ELSE
          channel = '#{prefix}.oban_update';
          notice = json_build_object('queue', NEW.queue, 'new_state', NEW.state, 'old_state', OLD.state);
        END IF;

        PERFORM pg_notify(channel, notice::text);

        RETURN NULL;
      END;
      $$ LANGUAGE plpgsql;
      """

      execute "DROP TRIGGER IF EXISTS oban_notify ON #{prefix}.oban_jobs"

      execute """
      CREATE TRIGGER oban_notify
      AFTER INSERT OR UPDATE OF state ON #{prefix}.oban_jobs
      FOR EACH ROW EXECUTE PROCEDURE #{prefix}.oban_jobs_notify();
      """

      execute "COMMENT ON TABLE #{prefix}.oban_jobs IS '1'"
    end

    def down(prefix) do
      execute "DROP TRIGGER IF EXISTS oban_notify ON #{prefix}.oban_jobs"
      execute "DROP FUNCTION #{prefix}.oban_jobs_notify()"

      drop_if_exists table(:oban_jobs, prefix: prefix)

      execute "DROP TYPE IF EXISTS #{prefix}.oban_job_state"
    end
  end

  defmodule V2 do
    @moduledoc false

    use Ecto.Migration

    def up(prefix) do
      # We only need the scheduled_at index for scheduled and available jobs
      drop_if_exists index(:oban_jobs, [:scheduled_at], prefix: prefix)

      state = "#{prefix}.oban_job_state"

      create index(:oban_jobs, [:scheduled_at],
               where: "state in ('available'::#{state}, 'scheduled'::#{state})",
               prefix: prefix
             )

      create constraint(:oban_jobs, :worker_length,
               check: "char_length(worker) > 0 AND char_length(worker) < 128",
               prefix: prefix
             )

      create constraint(:oban_jobs, :queue_length,
               check: "char_length(queue) > 0 AND char_length(queue) < 128",
               prefix: prefix
             )

      execute """
      CREATE OR REPLACE FUNCTION #{prefix}.oban_wrap_id(value bigint) RETURNS int AS $$
      BEGIN
        RETURN (CASE WHEN value > 2147483647 THEN mod(value, 2147483647) ELSE value END)::int;
      END;
      $$ LANGUAGE plpgsql IMMUTABLE;
      """

      execute "COMMENT ON TABLE #{prefix}.oban_jobs IS '2'"
    end

    def down(prefix) do
      drop_if_exists constraint(:oban_jobs, :queue_length, prefix: prefix)
      drop_if_exists constraint(:oban_jobs, :worker_length, prefix: prefix)

      drop_if_exists index(:oban_jobs, [:scheduled_at], prefix: prefix)
      create index(:oban_jobs, [:scheduled_at], prefix: prefix)

      execute("DROP FUNCTION #{prefix}.oban_wrap_id(value bigint)")

      execute "COMMENT ON TABLE #{prefix}.oban_jobs IS '1'"
    end
  end

  defmodule V3 do
    @moduledoc false

    use Ecto.Migration

    import Oban.Migrations.Macros

    def up(prefix) do
      alter table(:oban_jobs, prefix: prefix) do
        add :attempted_by, :text
      end

      create_if_not_exists table(:oban_beats, primary_key: false, prefix: prefix) do
        add :node, :text, null: false
        add :queue, :text, null: false
        add :limit, :integer, null: false
        add :paused, :boolean, null: false, default: false
        add :running, {:array, :integer}, null: false, default: []

        add :inserted_at, :utc_datetime_usec, null: false, default: now()
        add :started_at, :utc_datetime_usec, null: false
      end

      create_if_not_exists index(:oban_beats, [:inserted_at], prefix: prefix)

      execute "COMMENT ON TABLE #{prefix}.oban_jobs IS '3'"
    end

    def down(prefix) do
      alter table(:oban_jobs, prefix: prefix) do
        remove :attempted_by
      end

      drop_if_exists table(:oban_beats, prefix: prefix)

      execute "COMMENT ON TABLE #{prefix}.oban_jobs IS '2'"
    end
  end

  defmodule V4 do
    @moduledoc false

    # Dropping the `oban_wrap_id` function is isolated to allow progressive rollout.

    use Ecto.Migration

    def up(prefix) do
      execute("DROP FUNCTION IF EXISTS #{prefix}.oban_wrap_id(value bigint)")

      execute "COMMENT ON TABLE #{prefix}.oban_jobs IS '4'"
    end

    def down(prefix) do
      execute """
      CREATE OR REPLACE FUNCTION #{prefix}.oban_wrap_id(value bigint) RETURNS int AS $$
      BEGIN
        RETURN (CASE WHEN value > 2147483647 THEN mod(value, 2147483647) ELSE value END)::int;
      END;
      $$ LANGUAGE plpgsql IMMUTABLE;
      """

      execute "COMMENT ON TABLE #{prefix}.oban_jobs IS '3'"
    end
  end
end
