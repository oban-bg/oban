defmodule Oban.Migrations.V06 do
  @moduledoc false

  use Ecto.Migration

  def up(_opts) do
    # This used to modify oban_beats, which aren't included anymore
  end

  def down(_opts) do
    # This used to modify oban_beats, which aren't included anymore
  end
end
