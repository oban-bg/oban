defmodule Oban.Engines.Basic do
  @moduledoc """
  The default engine for use with Postgres databases.

  ## Usage

  This is the default engine, no additional configuration is necessary:

      Oban.start_link(repo: MyApp.Repo, queues: [default: 10])
  """

  @behaviour Oban.Engine

  import Ecto.Query
  import DateTime, only: [utc_now: 0]

  alias Ecto.Changeset
  alias Oban.{Config, Engine, Job, Repo}

  @impl Engine
  def init(%Config{} = conf, opts) do
    if Keyword.has_key?(opts, :limit) do
      with :ok <- Enum.reduce_while(opts, :ok, &validate_meta_opt/2) do
        meta =
          opts
          |> Map.new()
          |> Map.put_new(:paused, false)
          |> Map.put_new(:refresh_interval, :timer.seconds(30))
          |> Map.put_new(:uuid, Ecto.UUID.generate())
          |> Map.merge(%{name: conf.name, node: conf.node})
          |> Map.merge(%{started_at: utc_now(), updated_at: utc_now()})

        {:ok, meta}
      end
    else
      {:error, ArgumentError.exception("missing required option :limit")}
    end
  end

  @impl Engine
  def put_meta(_conf, %{} = meta, key, value) do
    Map.put(meta, key, value)
  end

  @impl Engine
  def check_meta(_conf, %{} = meta, %{} = running) do
    jids = for {_, {_, exec}} <- running, do: exec.job.id

    Map.put(meta, :running, jids)
  end

  @impl Engine
  def refresh(_conf, %{} = meta) do
    %{meta | updated_at: utc_now()}
  end

  @impl Engine
  def shutdown(_conf, %{} = meta) do
    %{meta | paused: true}
  end

  @impl Engine
  def insert_job(%Config{} = conf, %Changeset{} = changeset, opts) do
    fun = fn -> insert_unique(conf, changeset, opts) end

    with {:ok, result} <- Repo.transaction(conf, fun), do: result
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

  def fetch_jobs(%Config{} = conf, %{} = meta, running) do
    demand = meta.limit - map_size(running)

    subset_query =
      Job
      |> select([:id])
      |> where([j], j.state == "available")
      |> where([j], j.queue == ^meta.queue)
      |> order_by(asc: :priority, asc: :scheduled_at, asc: :id)
      |> limit(^demand)
      |> lock("FOR UPDATE SKIP LOCKED")

    # The Postgres planner may choose to generate a plan that executes a nested loop over the
    # LIMITing subquery, causing more UPDATEs than LIMIT. That could cause unexpected updates,
    # including attempts > max_attempts in some cases. The solution is to use a CTE as an
    # "optimization fence" that forces Postgres _not_ to optimize the query.
    #
    # The odd "subset" fragment is required to prevent Ecto from applying the prefix to the name
    # of the CTE, e.g. "public"."subset".
    query =
      Job
      |> with_cte("subset", as: ^subset_query, materialized: true)
      |> join(:inner, [j], x in fragment(~s("subset")), on: true)
      |> where([j, x], j.id == x.id)
      |> where([j, _], j.attempt < j.max_attempts)
      |> select([j, _], j)

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

    subquery =
      queryable
      |> select([:id, :state])
      |> where([j], j.state in ~w(scheduled retryable))
      |> where([j], not is_nil(j.queue))
      |> where([j], j.scheduled_at <= ^DateTime.utc_now())
      |> limit(^limit)

    query =
      Job
      |> join(:inner, [j], x in subquery(subquery), on: j.id == x.id)
      |> select([j, x], %{id: j.id, queue: j.queue, state: x.state})

    {_count, staged} = Repo.update_all(conf, query, set: [state: "available"])

    {:ok, staged}
  end

  @impl Engine
  def prune_jobs(%Config{} = conf, queryable, opts) do
    max_age = Keyword.fetch!(opts, :max_age)
    limit = Keyword.fetch!(opts, :limit)
    time = DateTime.add(DateTime.utc_now(), -max_age)

    subquery =
      queryable
      |> select([:id, :queue, :state])
      |> where([j], j.state in ~w(completed cancelled discarded))
      |> where([j], not is_nil(j.queue))
      |> where([j], j.scheduled_at < ^time)
      |> limit(^limit)

    query =
      Job
      |> join(:inner, [j], x in subquery(subquery), on: j.id == x.id)
      |> select([_, x], map(x, [:id, :queue, :state]))

    {_count, pruned} = Repo.delete_all(conf, query)

    {:ok, pruned}
  end

  @impl Engine
  def complete_job(%Config{} = conf, %Job{} = job) do
    Repo.update_all(
      conf,
      where(Job, id: ^job.id),
      set: [state: "completed", completed_at: utc_now()]
    )

    :ok
  end

  @impl Engine
  def discard_job(%Config{} = conf, %Job{} = job) do
    updates = [
      set: [state: "discarded", discarded_at: utc_now()],
      push: [errors: Job.format_attempt(job)]
    ]

    Repo.update_all(conf, where(Job, id: ^job.id), updates)

    :ok
  end

  @impl Engine
  def error_job(%Config{} = conf, %Job{} = job, seconds) when is_integer(seconds) do
    updates = [
      set: [state: "retryable", scheduled_at: seconds_from_now(seconds)],
      push: [errors: Job.format_attempt(job)]
    ]

    Repo.update_all(conf, where(Job, id: ^job.id), updates)

    :ok
  end

  @impl Engine
  def snooze_job(%Config{} = conf, %Job{id: id}, seconds) when is_integer(seconds) do
    updates = [
      set: [state: "scheduled", scheduled_at: seconds_from_now(seconds)],
      inc: [max_attempts: 1]
    ]

    Repo.update_all(conf, where(Job, id: ^id), updates)

    :ok
  end

  @impl Engine
  def cancel_job(%Config{} = conf, %Job{} = job) do
    query = where(Job, id: ^job.id)

    query =
      if is_map(job.unsaved_error) do
        update(query, [j],
          set: [state: "cancelled", cancelled_at: ^utc_now()],
          push: [errors: ^Job.format_attempt(job)]
        )
      else
        query
        |> where([j], j.state not in ["cancelled", "completed", "discarded"])
        |> update(set: [state: "cancelled", cancelled_at: ^utc_now()])
      end

    Repo.update_all(conf, query, [])

    :ok
  end

  @impl Engine
  def cancel_all_jobs(%Config{} = conf, queryable) do
    subquery = where(queryable, [j], j.state not in ["cancelled", "completed", "discarded"])

    query =
      Job
      |> join(:inner, [j], x in subquery(subquery), on: j.id == x.id)
      |> select([_, x], map(x, [:id, :queue, :state]))

    {_, jobs} = Repo.update_all(conf, query, set: [state: "cancelled", cancelled_at: utc_now()])

    {:ok, jobs}
  end

  @impl Engine
  def retry_job(%Config{} = conf, %Job{id: id}) do
    retry_all_jobs(conf, where(Job, [j], j.id == ^id))

    :ok
  end

  @impl Engine
  def retry_all_jobs(%Config{} = conf, queryable) do
    subquery = where(queryable, [j], j.state not in ["available", "executing"])

    query =
      Job
      |> join(:inner, [j], x in subquery(subquery), on: j.id == x.id)
      |> select([_, x], map(x, [:id, :queue, :state]))
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

    {_, jobs} = Repo.update_all(conf, query, [])

    {:ok, jobs}
  end

  # Validation

  defp validate_meta_opt(opt, _acc) do
    case validate_meta_opt(opt) do
      {:error, error} -> {:halt, {:error, ArgumentError.exception(error)}}
      _ -> {:cont, :ok}
    end
  end

  defp validate_meta_opt({:limit, limit}) do
    unless is_integer(limit) and limit > 0 do
      {:error, "expected :limit to be an integer greater than 0, got: #{inspect(limit)}"}
    end
  end

  defp validate_meta_opt({:paused, paused}) do
    unless is_boolean(paused) do
      {:error, "expected :paused to be a boolean, got: #{inspect(paused)}"}
    end
  end

  defp validate_meta_opt({:queue, queue}) do
    unless is_atom(queue) or (is_binary(queue) and byte_size(queue) > 0) do
      {:error, "expected :queue to be an atom or binary, got: #{inspect(queue)}"}
    end
  end

  defp validate_meta_opt({:refresh_interval, interval}) do
    unless is_integer(interval) and interval > 0 do
      {:error, "expected :refresh_interval to be positive integer, got: #{inspect(interval)}"}
    end
  end

  defp validate_meta_opt({:validate, _}), do: :ok

  defp validate_meta_opt(opt), do: {:error, "unexpected option #{inspect(opt)}"}

  # Insertion

  defp insert_unique(conf, changeset, opts) do
    opts = Keyword.put(opts, :on_conflict, :nothing)

    with {:ok, query, lock_key} <- unique_query(changeset),
         :ok <- acquire_lock(conf, lock_key),
         {:ok, job} <- fetch_job(conf, query, opts),
         {:ok, job} <- resolve_conflict(conf, job, changeset, opts) do
      {:ok, %Job{job | conflict?: true}}
    else
      {:error, :locked} ->
        with {:ok, job} <- Changeset.apply_action(changeset, :insert) do
          {:ok, %Job{job | conflict?: true}}
        end

      nil ->
        Repo.insert(conf, changeset, opts)

      error ->
        error
    end
  end

  defp resolve_conflict(conf, job, changeset, opts) do
    case Changeset.fetch_change(changeset, :replace) do
      {:ok, replace} ->
        keys = Keyword.get(replace, String.to_existing_atom(job.state), [])

        Repo.update(
          conf,
          Changeset.change(job, Map.take(changeset.changes, keys)),
          opts
        )

      :error ->
        {:ok, job}
    end
  rescue
    error in [Ecto.StaleEntryError] ->
      {:error, error}
  end

  defp unique_query(%{changes: %{unique: %{} = unique}} = changeset) do
    %{fields: fields, keys: keys, period: period, states: states, timestamp: timestamp} = unique

    keys = Enum.map(keys, &to_string/1)
    states = Enum.map(states, &to_string/1)
    dynamic = Enum.reduce(fields, true, &unique_field({changeset, &1, keys}, &2))
    lock_key = :erlang.phash2([keys, states, dynamic])

    query =
      Job
      |> where([j], j.state in ^states)
      |> since_period(period, timestamp)
      |> where(^dynamic)
      |> limit(1)

    {:ok, query, lock_key}
  end

  defp unique_query(_changeset), do: nil

  defp unique_field({changeset, field, keys}, acc) when field in [:args, :meta] do
    value = unique_map_values(changeset, field, keys)

    cond do
      value == %{} ->
        dynamic([j], fragment("? <@ ?", field(j, ^field), ^value) and ^acc)

      keys == [] ->
        dynamic(
          [j],
          fragment("? @> ?", field(j, ^field), ^value) and
            fragment("? <@ ?", field(j, ^field), ^value) and ^acc
        )

      true ->
        dynamic([j], fragment("? @> ?", field(j, ^field), ^value) and ^acc)
    end
  end

  defp unique_field({changeset, field, _}, acc) do
    value = Changeset.get_field(changeset, field)

    dynamic([j], field(j, ^field) == ^value and ^acc)
  end

  defp unique_map_values(changeset, field, keys) do
    case keys do
      [] ->
        Changeset.get_field(changeset, field)

      [_ | _] ->
        changeset
        |> Changeset.get_field(field)
        |> Map.new(fn {key, val} -> {to_string(key), val} end)
        |> Map.take(keys)
    end
  end

  defp since_period(query, :infinity, _timestamp), do: query

  defp since_period(query, period, timestamp) do
    where(query, [j], field(j, ^timestamp) >= ^seconds_from_now(-period))
  end

  defp acquire_lock(%{testing: :disabled} = conf, base_key) do
    pref_key = :erlang.phash2(conf.prefix)
    lock_key = pref_key + base_key

    case Repo.query(conf, "SELECT pg_try_advisory_xact_lock($1)", [lock_key]) do
      {:ok, %{rows: [[true]]}} -> :ok
      _ -> {:error, :locked}
    end
  end

  defp acquire_lock(_conf, _key), do: :ok

  defp fetch_job(conf, query, opts) do
    case Repo.one(conf, query, Keyword.put(opts, :prepare, :unnamed)) do
      nil -> nil
      job -> {:ok, job}
    end
  end

  defp seconds_from_now(seconds), do: DateTime.add(utc_now(), seconds, :second)
end
