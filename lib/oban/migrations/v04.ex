defmodule Oban.Migrations.V04 do
  @moduledoc false

  use Ecto.Migration

  def up(%{prefix: prefix}) do
    execute("DROP FUNCTION IF EXISTS #{prefix}.oban_wrap_id(value bigint)")
  end

  def down(%{prefix: prefix}) do
    execute """
    CREATE OR REPLACE FUNCTION #{prefix}.oban_wrap_id(value bigint) RETURNS int AS $$
    BEGIN
      RETURN (CASE WHEN value > 2147483647 THEN mod(value, 2147483647) ELSE value END)::int;
    END;
    $$ LANGUAGE plpgsql IMMUTABLE;
    """
  end
end
