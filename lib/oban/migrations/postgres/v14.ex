defmodule Oban.Migrations.Postgres.V14 do
  @moduledoc false

  use Ecto.Migration

  def up(%{quoted_prefix: quoted}) do
    execute """
    DO $$
    BEGIN
      IF NOT ('{suspended}' <@ enum_range(NULL::#{quoted}.oban_job_state)::text[]) THEN
        ALTER TYPE #{quoted}.oban_job_state ADD VALUE 'suspended' BEFORE 'scheduled';
      END IF;
    END$$;
    """
  end

  def down(_opts), do: :ok
end
