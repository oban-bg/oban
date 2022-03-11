defmodule Oban.Migrations.V04 do
  @moduledoc false

  use Ecto.Migration

  def up(%{quoted_prefix: quoted}) do
    execute("DROP FUNCTION IF EXISTS #{quoted}.oban_wrap_id(value bigint)")
  end

  def down(%{quoted_prefix: quoted}) do
    execute """
    CREATE OR REPLACE FUNCTION #{quoted}.oban_wrap_id(value bigint) RETURNS int AS $$
    BEGIN
      RETURN (CASE WHEN value > 2147483647 THEN mod(value, 2147483647) ELSE value END)::int;
    END;
    $$ LANGUAGE plpgsql IMMUTABLE;
    """
  end
end
