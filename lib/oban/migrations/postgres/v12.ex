defmodule Oban.Migrations.Postgres.V12 do
  @moduledoc false

  use Ecto.Migration

  def up(%{prefix: prefix, quoted_prefix: quoted}) do
    drop constraint(:oban_jobs, :priority_range, prefix: prefix)

    create constraint(:oban_jobs, :non_negative_priority,
             check: "priority >= 0",
             validate: false,
             prefix: prefix
           )

    execute "DROP TRIGGER IF EXISTS oban_notify ON #{quoted}.oban_jobs"
    execute "DROP FUNCTION IF EXISTS #{quoted}.oban_jobs_notify()"
  end

  def down(%{escaped_prefix: escaped, prefix: prefix, quoted_prefix: quoted}) do
    drop constraint(:oban_jobs, :non_negative_priority, prefix: prefix)

    create constraint(:oban_jobs, :priority_range,
             check: "priority between 0 and 3",
             validate: false,
             prefix: prefix
           )

    execute """
    CREATE OR REPLACE FUNCTION #{quoted}.oban_jobs_notify() RETURNS trigger AS $$
    DECLARE
      channel text;
      notice json;
    BEGIN
      IF NEW.state = 'available' THEN
        channel = '#{escaped}.oban_insert';
        notice = json_build_object('queue', NEW.queue);

        PERFORM pg_notify(channel, notice::text);
      END IF;

      RETURN NULL;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER oban_notify
    AFTER INSERT ON #{quoted}.oban_jobs
    FOR EACH ROW EXECUTE PROCEDURE #{quoted}.oban_jobs_notify();
    """
  end
end
