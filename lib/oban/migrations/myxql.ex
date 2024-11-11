defmodule Oban.Migrations.MyXQL do
  @moduledoc false

  @behaviour Oban.Migration

  use Ecto.Migration

  @impl Oban.Migration
  def up(_opts) do
    states =
      :"ENUM('available', 'scheduled', 'executing', 'retryable', 'completed', 'cancelled', 'discarded')"

    create_if_not_exists table(:oban_jobs, primary_key: false) do
      add :id, :bigserial, primary_key: true
      add :state, states, null: false, default: "available"
      add :queue, :string, null: false, default: "default"
      add :worker, :string, null: false
      add :args, :json, null: false, default: %{}
      add :meta, :json, null: false, default: %{}
      add :tags, :json, null: false, default: fragment("('[]')")
      add :attempted_by, :json, null: false, default: fragment("('[]')")
      add :errors, :json, null: false, default: fragment("('[]')")
      add :attempt, :integer, null: false, default: 0
      add :max_attempts, :integer, null: false, default: 20
      add :priority, :integer, null: false, default: 0

      add :inserted_at, :utc_datetime_usec, null: false, default: fragment("(UTC_TIMESTAMP(6))")
      add :scheduled_at, :utc_datetime_usec, null: false, default: fragment("(UTC_TIMESTAMP(6))")
      add :attempted_at, :utc_datetime_usec
      add :cancelled_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec
      add :discarded_at, :utc_datetime_usec
    end

    create_if_not_exists table(:oban_peers, primary_key: false) do
      add :name, :string, null: false, primary_key: true
      add :node, :string, null: false
      add :started_at, :utc_datetime_usec, null: false
      add :expires_at, :utc_datetime_usec, null: false
    end

    create index(:oban_jobs, [:state, :queue, :priority, :scheduled_at, :id])

    create constraint(:oban_jobs, :attempt_range, check: "attempt between 0 and max_attempts")
    create constraint(:oban_jobs, :non_negative_priority, check: "priority >= 0")
    create constraint(:oban_jobs, :positive_max_attempts, check: "max_attempts > 0")

    create constraint(:oban_jobs, :queue_length,
             check: "char_length(queue) > 0 AND char_length(queue) < 128"
           )

    create constraint(:oban_jobs, :worker_length,
             check: "char_length(worker) > 0 AND char_length(worker) < 128"
           )

    :ok
  end

  @impl Oban.Migration
  def down(_opts) do
    drop_if_exists table(:oban_peers)
    drop_if_exists table(:oban_jobs)

    :ok
  end

  @impl Oban.Migration
  def migrated_version(_opts), do: 0
end
