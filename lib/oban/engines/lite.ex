defmodule Oban.Engines.Lite do
  @moduledoc false

  @behaviour Oban.Engine

  import DateTime, only: [utc_now: 0]
  import Ecto.Query

  alias Ecto.Changeset
  alias Oban.{Config, Engine, Job, Repo}

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
  defdelegate cancel_job(conf, job), to: Oban.Engines.Basic

  @impl Engine
  defdelegate complete_job(conf, job), to: Oban.Engines.Basic

  @impl Engine
  defdelegate discard_job(conf, job), to: Oban.Engines.Basic

  @impl Engine
  defdelegate error_job(conf, job, seconds), to: Oban.Engines.Basic

  @impl Engine
  defdelegate snooze_job(conf, job, seconds), to: Oban.Engines.Basic
end
