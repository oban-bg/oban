defmodule Oban.Migrations do
  @moduledoc false

  use Ecto.Migration

  @initial_version 1
  @current_version 8
  @default_prefix "public"

  def up(opts \\ []) when is_list(opts) do
    prefix = Keyword.get(opts, :prefix, @default_prefix)
    version = Keyword.get(opts, :version, @current_version)
    initial = min(migrated_version(repo(), prefix) + 1, @current_version)

    if initial <= version, do: change(prefix, initial..version, :up)
  end

  def down(opts \\ []) when is_list(opts) do
    prefix = Keyword.get(opts, :prefix, @default_prefix)
    version = Keyword.get(opts, :version, @initial_version)
    initial = max(migrated_version(repo(), prefix), @initial_version)

    if initial >= version, do: change(prefix, initial..version, :down)
  end

  def initial_version, do: @initial_version

  def current_version, do: @current_version

  def migrated_version(repo, prefix) do
    query = """
    SELECT description
    FROM pg_class
    LEFT JOIN pg_description ON pg_description.objoid = pg_class.oid
    LEFT JOIN pg_namespace ON pg_namespace.oid = pg_class.relnamespace
    WHERE pg_class.relname = 'oban_jobs'
    AND pg_namespace.nspname = '#{prefix}'
    """

    case repo.query(query) do
      {:ok, %{rows: [[version]]}} when is_binary(version) -> String.to_integer(version)
      _ -> 0
    end
  end

  defp change(prefix, range, direction) do
    for index <- range do
      [__MODULE__, "V#{index}"]
      |> Module.concat()
      |> apply(direction, [prefix])
    end
  end

  defmodule Helper do
    @moduledoc false

    defmacro now do
      quote do
        fragment("timezone('UTC', now())")
      end
    end

    def record_version(prefix, version) do
      execute "COMMENT ON TABLE #{prefix}.oban_jobs IS '#{version}'"
    end

    # Extracted into a helper function to facilitate sharing.
    def v1_oban_notify(prefix) do
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
    end

    def v2_oban_notify(prefix) do
      execute """
      CREATE OR REPLACE FUNCTION #{prefix}.oban_jobs_notify() RETURNS trigger AS $$
      DECLARE
        channel text;
        notice json;
      BEGIN
        IF NEW.state = 'available' THEN
          channel = '#{prefix}.oban_insert';
          notice = json_build_object('queue', NEW.queue, 'state', NEW.state);

          PERFORM pg_notify(channel, notice::text);
        END IF;

        RETURN NULL;
      END;
      $$ LANGUAGE plpgsql;
      """

      execute "DROP TRIGGER oban_notify ON #{prefix}.oban_jobs"

      execute """
      CREATE TRIGGER oban_notify
      AFTER INSERT ON #{prefix}.oban_jobs
      FOR EACH ROW EXECUTE PROCEDURE #{prefix}.oban_jobs_notify();
      """
    end
  end

  defmodule V1 do
    @moduledoc false

    use Ecto.Migration

    import Oban.Migrations.Helper

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

      v1_oban_notify(prefix)

      record_version(prefix, 1)
    end

    def down(prefix) do
      execute "DROP TRIGGER IF EXISTS oban_notify ON #{prefix}.oban_jobs"
      execute "DROP FUNCTION IF EXISTS #{prefix}.oban_jobs_notify()"

      drop_if_exists table(:oban_jobs, prefix: prefix)

      execute "DROP TYPE IF EXISTS #{prefix}.oban_job_state"
    end
  end

  defmodule V2 do
    @moduledoc false

    use Ecto.Migration

    import Oban.Migrations.Helper

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

      record_version(prefix, 2)
    end

    def down(prefix) do
      drop_if_exists constraint(:oban_jobs, :queue_length, prefix: prefix)
      drop_if_exists constraint(:oban_jobs, :worker_length, prefix: prefix)

      drop_if_exists index(:oban_jobs, [:scheduled_at], prefix: prefix)
      create index(:oban_jobs, [:scheduled_at], prefix: prefix)

      execute("DROP FUNCTION IF EXISTS #{prefix}.oban_wrap_id(value bigint)")

      record_version(prefix, 1)
    end
  end

  defmodule V3 do
    @moduledoc false

    use Ecto.Migration

    import Oban.Migrations.Helper

    def up(prefix) do
      alter table(:oban_jobs, prefix: prefix) do
        add_if_not_exists(:attempted_by, {:array, :text})
      end

      create_if_not_exists table(:oban_beats, primary_key: false, prefix: prefix) do
        add :node, :text, null: false
        add :queue, :text, null: false
        add :nonce, :text, null: false
        add :limit, :integer, null: false
        add :paused, :boolean, null: false, default: false
        add :running, {:array, :integer}, null: false, default: []

        add :inserted_at, :utc_datetime_usec, null: false, default: now()
        add :started_at, :utc_datetime_usec, null: false
      end

      create_if_not_exists index(:oban_beats, [:inserted_at], prefix: prefix)

      record_version(prefix, 3)
    end

    def down(prefix) do
      alter table(:oban_jobs, prefix: prefix) do
        remove_if_exists(:attempted_by, {:array, :text})
      end

      drop_if_exists table(:oban_beats, prefix: prefix)

      record_version(prefix, 2)
    end
  end

  defmodule V4 do
    @moduledoc false

    # Dropping the `oban_wrap_id` function is isolated to allow progressive rollout.

    use Ecto.Migration

    import Oban.Migrations.Helper

    def up(prefix) do
      execute("DROP FUNCTION IF EXISTS #{prefix}.oban_wrap_id(value bigint)")

      record_version(prefix, 4)
    end

    def down(prefix) do
      execute """
      CREATE OR REPLACE FUNCTION #{prefix}.oban_wrap_id(value bigint) RETURNS int AS $$
      BEGIN
        RETURN (CASE WHEN value > 2147483647 THEN mod(value, 2147483647) ELSE value END)::int;
      END;
      $$ LANGUAGE plpgsql IMMUTABLE;
      """

      record_version(prefix, 3)
    end
  end

  defmodule V5 do
    @moduledoc false

    use Ecto.Migration

    import Oban.Migrations.Helper

    def up(prefix) do
      drop_if_exists index(:oban_jobs, [:scheduled_at], prefix: prefix)
      drop_if_exists index(:oban_jobs, [:queue], prefix: prefix)
      drop_if_exists index(:oban_jobs, [:state], prefix: prefix)

      create_if_not_exists index(:oban_jobs, [:queue, :state, :scheduled_at, :id], prefix: prefix)

      record_version(prefix, 5)
    end

    def down(prefix) do
      drop_if_exists index(:oban_jobs, [:queue, :state, :scheduled_at, :id], prefix: prefix)

      state = "#{prefix}.oban_job_state"

      create_if_not_exists index(:oban_jobs, [:queue], prefix: prefix)
      create_if_not_exists index(:oban_jobs, [:state], prefix: prefix)

      create index(:oban_jobs, [:scheduled_at],
               where: "state in ('available'::#{state}, 'scheduled'::#{state})",
               prefix: prefix
             )

      record_version(prefix, 4)
    end
  end

  defmodule V6 do
    @moduledoc false

    use Ecto.Migration

    import Oban.Migrations.Helper

    def up(prefix) do
      execute "ALTER TABLE #{prefix}.oban_beats ALTER COLUMN running TYPE bigint[]"

      record_version(prefix, 6)
    end

    def down(prefix) do
      execute "ALTER TABLE #{prefix}.oban_beats ALTER COLUMN running TYPE integer[]"

      record_version(prefix, 5)
    end
  end

  defmodule V7 do
    @moduledoc false

    use Ecto.Migration

    import Oban.Migrations.Helper

    def up(prefix) do
      create_if_not_exists index(
                             :oban_jobs,
                             ["attempted_at desc", :id],
                             where: "state in ('completed', 'discarded')",
                             prefix: prefix,
                             name: :oban_jobs_attempted_at_id_index
                           )

      record_version(prefix, 7)
    end

    def down(prefix) do
      drop_if_exists index(:oban_jobs, [:attempted_at, :id], prefix: prefix)

      record_version(prefix, 6)
    end
  end

  defmodule V8 do
    @moduledoc false

    use Ecto.Migration

    import Oban.Migrations.Helper

    def up(prefix) do
      alter table(:oban_jobs, prefix: prefix) do
        add_if_not_exists(:discarded_at, :utc_datetime_usec)
        add_if_not_exists(:priority, :integer)
        add_if_not_exists(:tags, {:array, :string})
      end

      alter table(:oban_jobs, prefix: prefix) do
        modify :priority, :integer, default: 0
        modify :tags, {:array, :string}, default: []
      end

      drop_if_exists index(:oban_jobs, [:queue, :state, :scheduled_at, :id], prefix: prefix)

      create_if_not_exists index(:oban_jobs, [:queue, :state, :priority, :scheduled_at, :id],
                             prefix: prefix
                           )

      v2_oban_notify(prefix)

      record_version(prefix, 8)
    end

    def down(prefix) do
      drop_if_exists index(:oban_jobs, [:queue, :state, :priority, :scheduled_at, :id],
                       prefix: prefix
                     )

      create_if_not_exists index(:oban_jobs, [:queue, :state, :scheduled_at, :id], prefix: prefix)

      alter table(:oban_jobs, prefix: prefix) do
        remove_if_exists(:discarded_at, :utc_datetime_usec)
        remove_if_exists(:priority, :integer)
        remove_if_exists(:tags, {:array, :string})
      end

      v1_oban_notify(prefix)

      record_version(prefix, 7)
    end
  end
end
