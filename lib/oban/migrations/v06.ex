defmodule Oban.Migrations.V06 do
  @moduledoc false

  use Ecto.Migration

  def up(_prefix) do
    # This used to modify oban_beats, which aren't included anymore
  end

  def down(_prefix) do
    # This used to modify oban_beats, which aren't included anymore
  end
end
