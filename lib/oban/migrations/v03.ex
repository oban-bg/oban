defmodule Oban.Migrations.V03 do
  @moduledoc false

  use Ecto.Migration

  def up(prefix) do
    alter table(:oban_jobs, prefix: prefix) do
      add_if_not_exists(:attempted_by, {:array, :text})
    end

    create_if_not_exists table(:oban_beats, primary_key: false, prefix: prefix) do
      add :node, :text, null: false
      add :queue, :text, null: false
      add :nonce, :text, null: false
      add :limit, :integer, null: false
      add :paused, :boolean, null: false, default: false
      add :running, {:array, :integer}, null: false, default: []

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("timezone('UTC', now())")

      add :started_at, :utc_datetime_usec, null: false
    end

    create_if_not_exists index(:oban_beats, [:inserted_at], prefix: prefix)
  end

  def down(prefix) do
    alter table(:oban_jobs, prefix: prefix) do
      remove_if_exists(:attempted_by, {:array, :text})
    end

    drop_if_exists table(:oban_beats, prefix: prefix)
  end
end
