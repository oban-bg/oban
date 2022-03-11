defmodule Oban.Migrations.V11 do
  @moduledoc false

  use Ecto.Migration

  def up(%{prefix: prefix, quoted_prefix: quoted}) do
    create_if_not_exists table(:oban_peers, primary_key: false, prefix: prefix) do
      add :name, :text, null: false, primary_key: true
      add :node, :text, null: false
      add :started_at, :utc_datetime_usec, null: false
      add :expires_at, :utc_datetime_usec, null: false
    end

    execute "ALTER TABLE #{quoted}.oban_peers SET UNLOGGED"
  end

  def down(%{prefix: prefix}) do
    drop table(:oban_peers, prefix: prefix)
  end
end
