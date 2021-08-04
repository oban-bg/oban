defmodule Oban.Query do
  @moduledoc false

  import Ecto.Query
  import DateTime, only: [utc_now: 0]

  alias Ecto.{Changeset, Multi}
  alias Oban.{Config, Job, Repo}

  @type lock_key :: pos_integer()

  @spec fetch_or_insert_job(Config.t(), Job.changeset()) :: {:ok, Job.t()} | {:error, term()}
  def fetch_or_insert_job(conf, changeset) do
    fun = fn -> insert_unique(conf, changeset) end
    with {:ok, result} <- Repo.transaction(conf, fun), do: result
  end

  @spec fetch_or_insert_job(
          Config.t(),
          Multi.t(),
          Multi.name(),
          Job.changeset() | Job.changeset_fun()
        ) ::
          Multi.t()
  def fetch_or_insert_job(conf, multi, name, fun) when is_function(fun, 1) do
    Multi.run(multi, name, fn repo, changes ->
      insert_unique(%{conf | repo: repo}, fun.(changes))
    end)
  end

  def fetch_or_insert_job(conf, multi, name, changeset) do
    Multi.run(multi, name, fn repo, _changes ->
      insert_unique(%{conf | repo: repo}, changeset)
    end)
  end

  @spec insert_all_jobs(Config.t(), Job.changeset_list()) :: [Job.t()]
  def insert_all_jobs(%Config{} = conf, changesets) when is_list(changesets) do
    entries = Enum.map(changesets, &Job.to_map/1)

    case Repo.insert_all(conf, Job, entries, on_conflict: :nothing, returning: true) do
      {0, _} -> []
      {_count, jobs} -> jobs
    end
  end

  @spec insert_all_jobs(
          Config.t(),
          Multi.t(),
          Multi.name(),
          Job.changeset_list() | Job.changeset_list_fun()
        ) :: Multi.t()
  def insert_all_jobs(conf, multi, name, changesets) when is_list(changesets) do
    Multi.run(multi, name, fn repo, _changes ->
      {:ok, insert_all_jobs(%{conf | repo: repo}, changesets)}
    end)
  end

  def insert_all_jobs(conf, multi, name, changesets_fun) when is_function(changesets_fun, 1) do
    Multi.run(multi, name, fn repo, changes ->
      {:ok, insert_all_jobs(%{conf | repo: repo}, changesets_fun.(changes))}
    end)
  end

  @spec retry_job(Config.t(), pos_integer()) :: :ok
  def retry_job(conf, id) do
    query = where(Job, [j], j.id == ^id)

    retry_all_jobs(conf, query)

    :ok
  end

  @spec retry_all_jobs(Config.t(), Ecto.Queryable.t()) :: {:ok, integer()}
  def retry_all_jobs(conf, queryable) do
    query =
      queryable
      |> where([j], j.state not in ["available", "executing", "scheduled"])
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

    {count, _} = Repo.update_all(conf, query, [])

    {:ok, count}
  end

  @spec with_xact_lock(Config.t(), lock_key(), fun()) :: {:ok, any()} | {:error, any()}
  def with_xact_lock(%Config{} = conf, lock_key, fun) when is_function(fun, 0) do
    Repo.transaction(conf, fn ->
      case acquire_lock(conf, lock_key) do
        :ok -> fun.()
        _er -> false
      end
    end)
  end

  # Helpers

  defp insert_unique(%Config{} = conf, changeset) do
    query_opts = [on_conflict: :nothing]

    with {:ok, query, lock_key} <- unique_query(changeset),
         :ok <- acquire_lock(conf, lock_key, query_opts),
         {:ok, job} <- unprepared_one(conf, query, query_opts),
         {:ok, job} <- return_or_replace(conf, query_opts, job, changeset) do
      {:ok, %Job{job | conflict?: true}}
    else
      {:error, :locked} ->
        {:ok, Changeset.apply_changes(changeset)}

      nil ->
        Repo.insert(conf, changeset, query_opts)

      error ->
        error
    end
  end

  defp return_or_replace(conf, query_opts, job, changeset) do
    case Changeset.get_change(changeset, :replace, []) do
      [] ->
        {:ok, job}

      replace_keys ->
        Repo.update(
          conf,
          Ecto.Changeset.change(job, Map.take(changeset.changes, replace_keys)),
          query_opts
        )
    end
  end

  defp unique_query(%{changes: %{unique: %{} = unique}} = changeset) do
    %{fields: fields, keys: keys, period: period, states: states} = unique

    keys = Enum.map(keys, &to_string/1)
    states = Enum.map(states, &to_string/1)
    dynamic = Enum.reduce(fields, true, &unique_field({changeset, &1, keys}, &2))
    lock_key = :erlang.phash2([keys, states, dynamic])

    query =
      Job
      |> where([j], j.state in ^states)
      |> since_period(period)
      |> where(^dynamic)
      |> order_by(desc: :id)
      |> limit(1)

    {:ok, query, lock_key}
  end

  defp unique_query(_changeset), do: nil

  defp unique_field({changeset, :args, keys}, acc) do
    args =
      case keys do
        [] ->
          Changeset.get_field(changeset, :args)

        [_ | _] ->
          changeset
          |> Changeset.get_field(:args)
          |> Map.new(fn {key, val} -> {to_string(key), val} end)
          |> Map.take(keys)
      end

    dynamic([j], fragment("? @> ?", j.args, ^args) and ^acc)
  end

  defp unique_field({changeset, field, _}, acc) do
    value = Changeset.get_field(changeset, field)

    dynamic([j], field(j, ^field) == ^value and ^acc)
  end

  defp since_period(query, :infinity), do: query

  defp since_period(query, period) do
    since = DateTime.add(utc_now(), period * -1, :second)

    where(query, [j], j.inserted_at > ^since)
  end

  defp acquire_lock(conf, base_key, opts \\ []) do
    pref_key = :erlang.phash2(conf.prefix)
    lock_key = pref_key + base_key

    case Repo.query(conf, "SELECT pg_try_advisory_xact_lock($1)", [lock_key], opts) do
      {:ok, %{rows: [[true]]}} ->
        :ok

      _ ->
        {:error, :locked}
    end
  end

  # With certain unique option combinations Postgres will decide to use a `generic plan` instead
  # of a `custom plan`, which *drastically* impacts the unique query performance. Ecto doesn't
  # provide a way to opt out of prepared statements for a single query, so this function works
  # around the issue by forcing a raw SQL query.
  defp unprepared_one(conf, query, opts) do
    {raw_sql, bindings} = Repo.to_sql(conf, :all, query)

    case Repo.query(conf, raw_sql, bindings, opts) do
      {:ok, %{columns: columns, rows: [rows]}} -> {:ok, conf.repo.load(Job, {columns, rows})}
      _ -> nil
    end
  end
end
