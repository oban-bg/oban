defmodule Oban.Migrations.V06 do
  @moduledoc false

  use Ecto.Migration

  def up(prefix) do
    execute "ALTER TABLE #{prefix}.oban_beats ALTER COLUMN running TYPE bigint[]"
  end

  def down(prefix) do
    execute "ALTER TABLE #{prefix}.oban_beats ALTER COLUMN running TYPE integer[]"
  end
end
