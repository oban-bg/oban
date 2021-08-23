defmodule Oban.Migrations.V03 do
  @moduledoc false

  use Ecto.Migration

  def up(%{prefix: prefix}) do
    alter table(:oban_jobs, prefix: prefix) do
      add_if_not_exists(:attempted_by, {:array, :text})
    end
  end

  def down(%{prefix: prefix}) do
    alter table(:oban_jobs, prefix: prefix) do
      remove_if_exists(:attempted_by, {:array, :text})
    end
  end
end
