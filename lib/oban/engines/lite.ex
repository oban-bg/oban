defmodule Oban.Engines.Lite do
  @moduledoc false

  @behaviour Oban.Engine

  import DateTime, only: [utc_now: 0]
  import Ecto.Query

  alias Ecto.Changeset
  alias Oban.{Config, Engine, Job, Repo}

  # EctoSQLite3 doesn't implement `push` for updates, so a json_insert is required.
  defmacrop json_push(column, value) do
    quote do
      fragment("json_insert(?, '$[#]', ?)", unquote(column), unquote(value))
    end
  end

  @impl Engine
  defdelegate init(conf, opts), to: Oban.Engines.Basic

  @impl Engine
  defdelegate put_meta(conf, meta, key, value), to: Oban.Engines.Basic

  @impl Engine
  defdelegate check_meta(conf, meta, running), to: Oban.Engines.Basic

  @impl Engine
  defdelegate refresh(conf, meta), to: Oban.Engines.Basic

  @impl Engine
  defdelegate shutdown(conf, meta), to: Oban.Engines.Basic

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
  def complete_job(conf, job) do
    Repo.update_all(
      conf,
      where(Job, id: ^job.id),
      set: [state: "completed", completed_at: utc_now()]
    )

    :ok
  end

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
  def snooze_job(conf, job, seconds) do
    updates = [
      set: [state: "scheduled", scheduled_at: seconds_from_now(seconds)],
      inc: [max_attempts: 1]
    ]

    Repo.update_all(conf, where(Job, id: ^job.id), updates)

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

  defp seconds_from_now(seconds), do: DateTime.add(utc_now(), seconds, :second)

  defp encode_unsaved(job) do
    Jason.encode!(%{
      attempt: job.attempt,
      at: utc_now(),
      error: format_blamed(job.unsaved_error)
    })
  end

  # TODO: Share this somewhere, it is copied three times

  defp format_blamed(%{kind: kind, reason: error, stacktrace: stacktrace}) do
    {blamed, stacktrace} = Exception.blame(kind, error, stacktrace)

    Exception.format(kind, blamed, stacktrace)
  end
end
