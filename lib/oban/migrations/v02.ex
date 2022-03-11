defmodule Oban.Migrations.V02 do
  @moduledoc false

  use Ecto.Migration

  def up(%{prefix: prefix, quoted_prefix: quoted}) do
    # We only need the scheduled_at index for scheduled and available jobs
    drop_if_exists index(:oban_jobs, [:scheduled_at], prefix: prefix)

    state = "#{quoted}.oban_job_state"

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
    CREATE OR REPLACE FUNCTION #{quoted}.oban_wrap_id(value bigint) RETURNS int AS $$
    BEGIN
      RETURN (CASE WHEN value > 2147483647 THEN mod(value, 2147483647) ELSE value END)::int;
    END;
    $$ LANGUAGE plpgsql IMMUTABLE;
    """
  end

  def down(%{prefix: prefix, quoted_prefix: quoted}) do
    drop_if_exists constraint(:oban_jobs, :queue_length, prefix: prefix)
    drop_if_exists constraint(:oban_jobs, :worker_length, prefix: prefix)

    drop_if_exists index(:oban_jobs, [:scheduled_at], prefix: prefix)
    create index(:oban_jobs, [:scheduled_at], prefix: prefix)

    execute("DROP FUNCTION IF EXISTS #{quoted}.oban_wrap_id(value bigint)")
  end
end
