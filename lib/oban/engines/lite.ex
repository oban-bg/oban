defmodule Oban.Engines.Lite do
  @moduledoc false

  @behaviour Oban.Engine

  import DateTime, only: [utc_now: 0]
  import Ecto.Query

  alias Ecto.Changeset
  alias Oban.Engines.Basic
  alias Oban.{Config, Engine, Job, Repo}

  # EctoSQLite3 doesn't implement `push` for updates, so a json_insert is required.
  defmacrop json_push(column, value) do
    quote do
      fragment("json_insert(?, '$[#]', ?)", unquote(column), unquote(value))
    end
  end

  @impl Engine
  defdelegate init(conf, opts), to: Basic

  @impl Engine
  defdelegate put_meta(conf, meta, key, value), to: Basic

  @impl Engine
  defdelegate check_meta(conf, meta, running), to: Basic

  @impl Engine
  defdelegate refresh(conf, meta), to: Basic

  @impl Engine
  defdelegate shutdown(conf, meta), to: Basic

  @impl Engine
  def insert_job(%Config{} = conf, %Changeset{} = changeset, _opts) do
    Repo.insert(conf, changeset)
  end

  @impl Engine
  def insert_all_jobs(%Config{} = conf, changesets, opts) do
    jobs = Enum.map(changesets, &Job.to_map/1)
    opts = Keyword.merge(opts, on_conflict: :nothing, returning: true)

    with {_count, jobs} <- Repo.insert_all(conf, Job, jobs, opts), do: jobs
  end

  @impl Engine
  def fetch_jobs(_conf, %{paused: true} = meta, _running) do
    {:ok, {meta, []}}
  end

  def fetch_jobs(_conf, %{limit: limit} = meta, running) when map_size(running) >= limit do
    {:ok, {meta, []}}
  end

  def fetch_jobs(%Config{} = conf, meta, running) do
    demand = meta.limit - map_size(running)

    subset =
      Job
      |> select([:id])
      |> where([j], j.state == "available")
      |> where([j], j.queue == ^meta.queue)
      |> order_by([j], asc: j.priority, asc: j.scheduled_at, asc: j.id)
      |> limit(^demand)

    updates = [
      set: [state: "executing", attempted_at: utc_now(), attempted_by: [meta.node]],
      inc: [attempt: 1]
    ]

    query =
      Job
      |> where([j], j.id in subquery(subset))
      |> select([j, _], j)

    jobs =
      case Repo.update_all(conf, query, updates) do
        {0, nil} -> []
        {_count, jobs} -> jobs
      end

    {:ok, {meta, jobs}}
  end

  @impl Engine
  defdelegate complete_job(conf, job), to: Basic

  @impl Engine
  defdelegate snooze_job(conf, job, seconds), to: Basic

  @impl Engine
  def discard_job(conf, job) do
    query =
      Job
      |> where(id: ^job.id)
      |> update([j],
        set: [
          state: "discarded",
          discarded_at: ^utc_now(),
          errors: json_push(j.errors, ^encode_unsaved(job))
        ]
      )

    Repo.update_all(conf, query, [])

    :ok
  end

  @impl Engine
  def error_job(conf, job, seconds) do
    query =
      Job
      |> where(id: ^job.id)
      |> update([j],
        set: [
          state: "retryable",
          scheduled_at: ^seconds_from_now(seconds),
          errors: json_push(j.errors, ^encode_unsaved(job))
        ]
      )

    Repo.update_all(conf, query, [])

    :ok
  end

  @impl Engine
  def cancel_job(conf, job) do
    query =
      Job
      |> where(id: ^job.id)
      |> where([j], j.state not in ["cancelled", "completed", "discarded"])

    query =
      if is_map(job.unsaved_error) do
        update(query, [j],
          set: [
            state: "cancelled",
            cancelled_at: ^utc_now(),
            errors: json_push(j.errors, ^encode_unsaved(job))
          ]
        )
      else
        update(query, set: [state: "cancelled", cancelled_at: ^utc_now()])
      end

    Repo.update_all(conf, query, [])

    :ok
  end

  @impl Engine
  defdelegate cancel_all_jobs(conf, queryable), to: Basic

  @impl Engine
  def retry_job(conf, %Job{id: id}) do
    retry_all_jobs(conf, where(Job, [j], j.id == ^id))

    :ok
  end

  @impl Engine
  def retry_all_jobs(conf, queryable) do
    subquery = where(queryable, [j], j.state not in ["available", "executing"])

    query =
      Job
      |> join(:inner, [j], x in subquery(subquery), on: j.id == x.id)
      |> select([_, x], map(x, [:id, :queue, :state, :worker]))
      |> update([j],
        set: [
          state: "available",
          max_attempts: fragment("MAX(?, ? + 1)", j.max_attempts, j.attempt),
          scheduled_at: ^utc_now(),
          completed_at: nil,
          cancelled_at: nil,
          discarded_at: nil
        ]
      )

    {_, jobs} = Repo.update_all(conf, query, [])

    {:ok, jobs}
  end

  # Helpers

  defp seconds_from_now(seconds), do: DateTime.add(utc_now(), seconds, :second)

  defp encode_unsaved(job) do
    Jason.encode!(%{
      attempt: job.attempt,
      at: utc_now(),
      error: format_blamed(job.unsaved_error)
    })
  end

  defp format_blamed(%{kind: kind, reason: error, stacktrace: stacktrace}) do
    {blamed, stacktrace} = Exception.blame(kind, error, stacktrace)

    Exception.format(kind, blamed, stacktrace)
  end
end
