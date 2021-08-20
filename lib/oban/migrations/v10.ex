defmodule Oban.Migrations.V10 do
  @moduledoc false

  use Ecto.Migration

  def up(%{prefix: prefix}) do
    # These didn't have defaults out of consideration for older PG versions
    alter table(:oban_jobs, prefix: prefix) do
      modify :args, :map, default: %{}
      modify :priority, :integer, null: false
    end

    # These could happen from an insert_all call with invalid data
    create constraint(:oban_jobs, :priority_range,
             check: "priority between 0 and 3",
             prefix: prefix
           )

    create constraint(:oban_jobs, :positive_max_attempts,
             check: "max_attempts > 0",
             prefix: prefix
           )

    create constraint(:oban_jobs, :attempt_range,
             check: "attempt between 0 and max_attempts",
             prefix: prefix
           )

    # These are unused or unnecessary
    drop_if_exists index(:oban_jobs, [:args], name: :oban_jobs_args_vector, prefix: prefix)
    drop_if_exists index(:oban_jobs, [:worker], name: :oban_jobs_worker_gist, prefix: prefix)

    drop_if_exists index(:oban_jobs, [:attempted_at],
                     name: :oban_jobs_attempted_at_id_index,
                     prefix: prefix
                   )

    # These are necessary to keep unique checks fast in large tables
    create_if_not_exists index(:oban_jobs, [:args], using: :gin, prefix: prefix)
    create_if_not_exists index(:oban_jobs, [:meta], using: :gin, prefix: prefix)
  end

  def down(%{prefix: prefix}) do
    alter table(:oban_jobs, prefix: prefix) do
      modify :args, :map, default: nil
      modify :priority, :integer, null: true
    end

    drop_if_exists constraint(:oban_jobs, :attempt_range, prefix: prefix)
    drop_if_exists constraint(:oban_jobs, :positive_max_attempts, prefix: prefix)
    drop_if_exists constraint(:oban_jobs, :priority_range, prefix: prefix)
  end
end
