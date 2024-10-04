defmodule Oban.Engines.Dolphin do
  @moduledoc """
  An engine for running Oban with MySQL (via the MyXQL adapter).

  ## Usage

  Start an `Oban` instance using the `Dolphin` engine:

      Oban.start_link(
        engine: Oban.Engines.Dolphin,
        queues: [default: 10],
        repo: MyApp.Repo
      )
  """

  import DateTime, only: [utc_now: 0]
  import Ecto.Query

  alias Ecto.Changeset
  alias Oban.{Config, Engine, Job, Repo}
  alias Oban.Engines.Basic

  # EctoSQLite3 doesn't implement `push` for updates, so a json_insert is required.
  defmacrop json_push(column, value) do
    quote do
      fragment("json_array_append(?, '$[#]', ?)", unquote(column), unquote(value))
    end
  end

  @behaviour Oban.Engine

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
  defdelegate insert_job(conf, changeset, opts), to: Basic

  @impl Engine
  def insert_all_jobs(%Config{} = conf, changesets, opts) do
    jobs = Enum.map(changesets, &Job.to_map/1)
    opts = Keyword.merge(opts, on_conflict: :nothing)

    with {_count, _jobs} <- Repo.insert_all(conf, Job, jobs, opts) do
      Enum.map(changesets, &Changeset.apply_action!(&1, :insert))
    end
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

    subquery =
      Job
      |> select([:id])
      |> where([j], j.state == "available")
      |> where([j], j.queue == ^meta.queue)
      |> order_by(asc: :priority, asc: :scheduled_at, asc: :id)
      |> limit(^demand)
      # |> lock("FOR UPDATE SKIP LOCKED")

    query =
      Job
      |> where([j], j.id in subquery(subquery))
      |> where([j], j.attempt < j.max_attempts)
      # |> select([j, _], j)

    updates = [
      set: [state: "executing", attempted_at: utc_now(), attempted_by: [meta.node, meta.uuid]],
      inc: [attempt: 1]
    ]

    Repo.transaction(conf, fn ->
      {_count, jobs} = Repo.update_all(conf, query, updates)

      {meta, jobs}
    end)
  end

  @impl Engine
  def stage_jobs(%Config{} = conf, queryable, opts) do
    limit = Keyword.fetch!(opts, :limit)

    select_query =
      queryable
      |> select([j], map(j, [:id, :queue, :state, :worker]))
      |> where([j], j.state in ~w(scheduled retryable))
      |> where([j], j.scheduled_at <= ^utc_now())
      |> limit(^limit)

    staged = Repo.all(conf, select_query)

    if Enum.any?(staged) do
      Repo.update_all(conf, where(Job, [j], j.id in ^Enum.map(staged, & &1.id)),
        set: [state: "available"]
      )
    end

    {:ok, staged}
  end

  @impl Engine
  def prune_jobs(%Config{} = conf, queryable, opts) do
    max_age = Keyword.fetch!(opts, :max_age)
    limit = Keyword.fetch!(opts, :limit)
    time = DateTime.add(utc_now(), -max_age)

    select_query =
      queryable
      |> select([j], map(j, [:id, :queue, :state]))
      |> where([j], j.state == "completed" and j.scheduled_at < ^time)
      |> or_where([j], j.state == "cancelled" and j.cancelled_at < ^time)
      |> or_where([j], j.state == "discarded" and j.discarded_at < ^time)
      |> limit(^limit)

    pruned = Repo.all(conf, select_query)

    if Enum.any?(pruned) do
      Repo.delete_all(conf, where(Job, [j], j.id in ^Enum.map(pruned, & &1.id)))
    end

    {:ok, pruned}
  end

  @impl Engine
  def cancel_job(%Config{} = conf, job) do
    query = where(Job, id: ^job.id)

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
        query
        |> where([j], j.state not in ["cancelled", "completed", "discarded"])
        |> update(set: [state: "cancelled", cancelled_at: ^utc_now()])
      end

    Repo.update_all(conf, query, [])

    :ok
  end

  defp encode_unsaved(job) do
    job
    |> Job.format_attempt()
    |> Jason.encode!()
  end
end
