defmodule Oban.Migrations.V07 do
  @moduledoc false

  use Ecto.Migration

  def up(%{prefix: prefix}) do
    create_if_not_exists index(
                           :oban_jobs,
                           ["attempted_at desc", :id],
                           where: "state in ('completed', 'discarded')",
                           prefix: prefix,
                           name: :oban_jobs_attempted_at_id_index
                         )
  end

  def down(%{prefix: prefix}) do
    drop_if_exists index(:oban_jobs, [:attempted_at, :id], prefix: prefix)
  end
end
