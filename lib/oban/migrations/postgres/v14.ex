defmodule Oban.Migrations.Postgres.V14 do
  @moduledoc false

  use Ecto.Migration

  def up(%{quoted_prefix: quoted}) do
    execute "ALTER TYPE #{quoted}.oban_job_state ADD VALUE IF NOT EXISTS 'suspended' BEFORE 'scheduled'"
  end

  def down(_opts), do: :ok
end
