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

  alias Oban.{Config, Engine, Job, Repo}
  alias Oban.Engines.Basic

  defmacrop json_push(column, value) do
    quote do
      fragment("json_array_append(?, '$', ?)", unquote(column), unquote(value))
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
    # MySQL doesn't return a primary key from a bulk insert, which violates the insert_all_jobs
    # contract. Inserting one at a time is far less efficient, but it does what's required.
    {:ok, jobs} =
      Repo.transaction(conf, fn ->
        Enum.map(changesets, fn changeset ->
          case insert_job(conf, changeset, opts) do
            {:ok, job} ->
              job

            {:error, %Ecto.Changeset{} = changeset} ->
              raise Ecto.InvalidChangesetError, action: :insert, changeset: changeset

            {:error, reason} ->
              raise RuntimeError, inspect(reason)
          end
        end)
      end)

    jobs
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

    {:ok, jobs} =
      Repo.transaction(conf, fn ->
        fetch_query =
          Job
          |> where([j], j.state == "available")
          |> where([j], j.queue == ^meta.queue)
          |> where([j], j.attempt < j.max_attempts)
          |> order_by(asc: :priority, asc: :scheduled_at, asc: :id)
          |> limit(^demand)
          |> lock("FOR UPDATE SKIP LOCKED")

        jobs = Repo.all(conf, fetch_query)
        found_query = where(Job, [j], j.id in ^Enum.map(jobs, & &1.id))

        at = utc_now()
        by = [meta.node, meta.uuid]

        updates = [
          set: [state: "executing", attempted_at: at, attempted_by: by],
          inc: [attempt: 1]
        ]

        # MySQL doesn't support selecting in an update. To accomplish the required functionality
        # we have to select, then update. 
        Repo.update_all(conf, found_query, updates)

        Enum.map(
          jobs,
          &%{&1 | attempt: &1.attempt + 1, attempted_at: at, attempted_by: by, state: "executing"}
        )
      end)

    {:ok, {meta, jobs}}
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
  defdelegate complete_job(conf, job), to: Basic

  @impl Engine
  def discard_job(%Config{} = conf, job) do
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
  def error_job(%Config{} = conf, job, seconds) do
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
  defdelegate snooze_job(conf, job, seconds), to: Basic

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
        |> where([j], j.state not in ~w(cancelled completed discarded))
        |> update(set: [state: "cancelled", cancelled_at: ^utc_now()])
      end

    Repo.update_all(conf, query, [])

    :ok
  end

  @impl Engine
  def cancel_all_jobs(%Config{} = conf, queryable) do
    Repo.transaction(conf, fn ->
      jobs =
        queryable
        |> where([j], j.state not in ~w(cancelled completed discarded))
        |> select([j], map(j, [:id, :queue, :state]))
        |> lock("FOR UPDATE SKIP LOCKED")
        |> then(&Repo.all(conf, &1))

      query = where(Job, [j], j.id in ^Enum.map(jobs, & &1.id))

      Repo.update_all(conf, query, set: [state: "cancelled", cancelled_at: utc_now()])

      jobs
    end)
  end

  @impl Engine
  def retry_job(%Config{} = conf, %Job{id: id}) do
    retry_all_jobs(conf, where(Job, [j], j.id == ^id))

    :ok
  end

  @impl Engine
  def retry_all_jobs(%Config{} = conf, queryable) do
    Repo.transaction(conf, fn ->
      query =
        queryable
        |> where([j], j.state not in ~w(available executing))
        |> select([j], map(j, [:id, :queue, :state]))

      jobs = Repo.all(conf, query)

      update_query =
        Job
        |> where([j], j.id in ^Enum.map(jobs, & &1.id))
        |> update([j],
          set: [
            state: "available",
            max_attempts: fragment("GREATEST(?, ? + 1)", j.max_attempts, j.attempt),
            scheduled_at: ^utc_now(),
            completed_at: nil,
            cancelled_at: nil,
            discarded_at: nil
          ]
        )

      Repo.update_all(conf, update_query, [])

      Enum.map(jobs, &%{&1 | state: "available"})
    end)
  end

  defp encode_unsaved(job) do
    job
    |> Job.format_attempt()
    |> Jason.encode!()
  end

  defp seconds_from_now(seconds), do: DateTime.add(utc_now(), seconds, :second)
end
