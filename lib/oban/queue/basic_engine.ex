defmodule Oban.Queue.BasicEngine do
  @moduledoc false

  @behaviour Oban.Queue.Engine

  import Ecto.Query
  import DateTime, only: [utc_now: 0]

  alias Ecto.{Changeset, Multi}
  alias Oban.{Config, Job, Repo}
  alias Oban.Queue.Engine

  @impl Engine
  def init(%Config{} = conf, opts) do
    if Keyword.has_key?(opts, :limit) do
      with :ok <- Enum.reduce_while(opts, :ok, &validate_meta_opt/2) do
        meta =
          opts
          |> Map.new()
          |> Map.put_new(:paused, false)
          |> Map.put_new(:refresh_interval, :timer.seconds(30))
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
  def insert_job(%Config{} = conf, %Changeset{} = changeset) do
    fun = fn -> insert_unique(conf, changeset) end

    with {:ok, result} <- Repo.transaction(conf, fun), do: result
  end

  @impl Engine
  def insert_job(%Config{} = conf, %Multi{} = multi, name, fun) when is_function(fun, 1) do
    Multi.run(multi, name, fn repo, changes ->
      insert_unique(%{conf | repo: repo}, fun.(changes))
    end)
  end

  @impl Engine
  def insert_job(%Config{} = conf, %Multi{} = multi, name, %Changeset{} = changeset) do
    Multi.run(multi, name, fn repo, _changes ->
      insert_unique(%{conf | repo: repo}, changeset)
    end)
  end

  @impl Engine
  def insert_all_jobs(%Config{} = conf, changesets) do
    entries =
      changesets
      |> expand(%{})
      |> Enum.map(&Job.to_map/1)

    case Repo.insert_all(conf, Job, entries, on_conflict: :nothing, returning: true) do
      {0, _} -> []
      {_count, jobs} -> jobs
    end
  end

  @impl Engine
  def insert_all_jobs(%Config{} = conf, %Multi{} = multi, name, wrapper) do
    Multi.run(multi, name, fn repo, changes ->
      {:ok, insert_all_jobs(%{conf | repo: repo}, expand(wrapper, changes))}
    end)
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

    subset =
      Job
      |> select([:id])
      |> where([j], j.state == "available")
      |> where([j], j.queue == ^meta.queue)
      |> order_by([j], asc: j.priority, asc: j.scheduled_at, asc: j.id)
      |> limit(^demand)
      |> lock("FOR UPDATE SKIP LOCKED")

    updates = [
      set: [state: "executing", attempted_at: utc_now(), attempted_by: [meta.node]],
      inc: [attempt: 1]
    ]

    Repo.transaction(
      conf,
      fn ->
        query =
          Job
          |> where([j], j.id in subquery(subset))
          |> select([j, _], j)

        case Repo.update_all(conf, query, updates) do
          {0, nil} -> {meta, []}
          {_count, jobs} -> {meta, jobs}
        end
      end
    )
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
      push: [
        errors: %{attempt: job.attempt, at: utc_now(), error: format_blamed(job.unsaved_error)}
      ]
    ]

    Repo.update_all(conf, where(Job, id: ^job.id), updates)

    :ok
  end

  @impl Engine
  def error_job(%Config{} = conf, %Job{} = job, seconds) when is_integer(seconds) do
    updates = [
      set: [state: "retryable", scheduled_at: seconds_from_now(seconds)],
      push: [
        errors: %{attempt: job.attempt, at: utc_now(), error: format_blamed(job.unsaved_error)}
      ]
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
  def cancel_job(%Config{} = conf, %Job{id: id}) do
    query = where(Job, [j], j.id == ^id)

    cancel_all_jobs(conf, query)

    :ok
  end

  @impl Engine
  def cancel_all_jobs(%Config{} = conf, queryable) do
    all_executing = fn _repo, _changes ->
      query =
        queryable
        |> where(state: "executing")
        |> select([:id])

      {:ok, Repo.all(conf, query)}
    end

    cancel_query =
      queryable
      |> where([j], j.state not in ["completed", "discarded", "cancelled"])
      |> update([j], set: [state: "cancelled", cancelled_at: ^utc_now()])

    multi =
      Multi.new()
      |> Multi.run(:executing, all_executing)
      |> Multi.update_all(:cancelled, cancel_query, [], log: conf.log, prefix: conf.prefix)

    {:ok, %{executing: executing, cancelled: {count, _}}} = Repo.transaction(conf, multi)

    {:ok, {count, executing}}
  end

  @impl Engine
  def retry_job(%Config{} = conf, %Job{id: id}) do
    query = where(Job, [j], j.id == ^id)

    retry_all_jobs(conf, query)

    :ok
  end

  @impl Engine
  def retry_all_jobs(%Config{} = conf, queryable) do
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

  defp insert_unique(conf, changeset) do
    query_opts = [on_conflict: :nothing]

    with {:ok, query, lock_key} <- unique_query(changeset),
         :ok <- acquire_lock(conf, lock_key),
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

  defp unique_field({changeset, :meta, keys}, acc) do
    meta =
      case keys do
        [] ->
          Changeset.get_field(changeset, :meta)

        [_ | _] ->
          changeset
          |> Changeset.get_field(:meta)
          |> Map.new(fn {key, val} -> {to_string(key), val} end)
          |> Map.take(keys)
      end

    dynamic([j], fragment("? @> ?", j.meta, ^meta) and ^acc)
  end

  defp unique_field({changeset, field, _}, acc) do
    value = Changeset.get_field(changeset, field)

    dynamic([j], field(j, ^field) == ^value and ^acc)
  end

  defp since_period(query, :infinity), do: query

  defp since_period(query, period) do
    since = DateTime.add(utc_now(), period * -1, :second)

    where(query, [j], j.inserted_at >= ^since)
  end

  defp acquire_lock(conf, base_key) do
    pref_key = :erlang.phash2(conf.prefix)
    lock_key = pref_key + base_key

    case Repo.query(conf, "SELECT pg_try_advisory_xact_lock($1)", [lock_key]) do
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

  # Changeset Helpers

  @doc false
  def expand(fun, changes) when is_function(fun, 1), do: expand(fun.(changes), changes)
  def expand(%{changesets: changesets}, _), do: expand(changesets, %{})
  def expand(changesets, _) when is_list(changesets), do: changesets

  # Other Helpers

  defp seconds_from_now(seconds), do: DateTime.add(utc_now(), seconds, :second)

  defp format_blamed(%{kind: kind, reason: error, stacktrace: stacktrace}) do
    {blamed, stacktrace} = Exception.blame(kind, error, stacktrace)

    Exception.format(kind, blamed, stacktrace)
  end
end
