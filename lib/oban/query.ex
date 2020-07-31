defmodule Oban.Query do
  @moduledoc false

  import Ecto.Query
  import DateTime, only: [utc_now: 0]

  alias Ecto.{Changeset, Multi}
  alias Oban.{Config, Job}

  @spec fetch_available_jobs(Config.t(), binary(), binary(), pos_integer()) :: {:ok, [Job.t()]}
  def fetch_available_jobs(%Config{} = conf, queue, nonce, demand) do
    %Config{node: node, prefix: prefix, repo: repo, log: log} = conf

    subset =
      Job
      |> select([:id])
      |> where([j], j.state == "available")
      |> where([j], j.queue == ^queue)
      |> order_by([j], asc: j.priority, asc: j.scheduled_at, asc: j.id)
      |> limit(^demand)
      |> lock("FOR UPDATE SKIP LOCKED")

    updates = [
      set: [state: "executing", attempted_at: utc_now(), attempted_by: [node, queue, nonce]],
      inc: [attempt: 1]
    ]

    repo.transaction(
      fn ->
        Job
        |> where([j], j.id in subquery(subset))
        |> select([j, _], j)
        |> repo.update_all(updates, log: log, prefix: prefix)
        |> case do
          {0, nil} -> []
          {_count, jobs} -> jobs
        end
      end,
      log: log
    )
  end

  @spec fetch_or_insert_job(Config.t(), Changeset.t()) :: {:ok, Job.t()} | {:error, Changeset.t()}
  def fetch_or_insert_job(%Config{repo: repo, log: log} = conf, changeset) do
    fun = fn -> insert_unique(conf, changeset) end

    with {:ok, result} <- repo.transaction(fun, log: log), do: result
  end

  @spec fetch_or_insert_job(Config.t(), Multi.t(), Multi.name(), fun() | Changeset.t()) ::
          Multi.t()
  def fetch_or_insert_job(config, multi, name, fun) when is_function(fun, 1) do
    Multi.run(multi, name, fn repo, changes ->
      insert_unique(%{config | repo: repo}, fun.(changes))
    end)
  end

  def fetch_or_insert_job(config, multi, name, changeset) do
    Multi.run(multi, name, fn repo, _changes ->
      insert_unique(%{config | repo: repo}, changeset)
    end)
  end

  @spec insert_all_jobs(Config.t(), [Changeset.t(Job.t())]) :: [Job.t()]
  def insert_all_jobs(%Config{} = conf, changesets) when is_list(changesets) do
    %Config{prefix: prefix, repo: repo, log: log} = conf

    entries = Enum.map(changesets, &Job.to_map/1)
    opts = [log: log, on_conflict: :nothing, prefix: prefix, returning: true]

    case repo.insert_all(Job, entries, opts) do
      {0, _} -> []
      {_count, jobs} -> jobs
    end
  end

  @spec insert_all_jobs(Config.t(), Multi.t(), Multi.name(), [Changeset.t()]) :: Multi.t()
  def insert_all_jobs(config, multi, name, changesets) when is_list(changesets) do
    Multi.run(multi, name, fn repo, _changes ->
      {:ok, insert_all_jobs(%{config | repo: repo}, changesets)}
    end)
  end

  @spec stage_scheduled_jobs(Config.t(), binary(), opts :: keyword()) :: {integer(), nil}
  def stage_scheduled_jobs(%Config{} = conf, queue, opts \\ []) do
    %Config{prefix: prefix, repo: repo, log: log} = conf

    max_scheduled_at = Keyword.get(opts, :max_scheduled_at, utc_now())

    subset =
      Job
      |> select([j], j.id)
      |> where([j], j.state in ["scheduled", "retryable"])
      |> where([j], j.queue == ^queue)
      |> where([j], j.scheduled_at <= ^max_scheduled_at)
      |> lock("FOR UPDATE SKIP LOCKED")

    repo.transaction(
      fn ->
        Job
        |> where([j], j.id in subquery(subset))
        |> repo.update_all([set: [state: "available"]], log: log, prefix: prefix)
      end,
      log: log
    )
  end

  @spec complete_job(Config.t(), Job.t()) :: :ok
  def complete_job(%Config{prefix: prefix, repo: repo, log: log}, %Job{id: id}) do
    repo.update_all(
      where(Job, id: ^id),
      [set: [state: "completed", completed_at: utc_now()]],
      log: log,
      prefix: prefix
    )

    :ok
  end

  @spec discard_job(Config.t(), Job.t()) :: :ok
  def discard_job(%Config{prefix: prefix, repo: repo, log: log}, %Job{} = job) do
    updates = [
      set: [state: "discarded", discarded_at: utc_now()],
      push: [
        errors: %{attempt: job.attempt, at: utc_now(), error: format_blamed(job.unsaved_error)}
      ]
    ]

    repo.update_all(
      where(Job, id: ^job.id),
      updates,
      log: log,
      prefix: prefix
    )

    :ok
  end

  @cancellable_states ~w(available scheduled retryable)

  @spec cancel_job(Config.t(), pos_integer()) :: :ok | :ignored
  def cancel_job(%Config{prefix: prefix, repo: repo, log: log}, job_id) do
    query = where(Job, [j], j.id == ^job_id and j.state in @cancellable_states)
    updates = [set: [state: "discarded", discarded_at: utc_now()]]

    case repo.update_all(query, updates, log: log, prefix: prefix) do
      {1, nil} -> :ok
      {0, nil} -> :ignored
    end
  end

  @spec snooze_job(Config.t(), Job.t(), pos_integer()) :: :ok
  def snooze_job(%Config{prefix: prefix, repo: repo, log: log}, %Job{id: id}, seconds) do
    scheduled_at = DateTime.add(utc_now(), seconds)

    updates = [
      set: [state: "scheduled", scheduled_at: scheduled_at],
      inc: [max_attempts: 1]
    ]

    repo.update_all(where(Job, id: ^id), updates, log: log, prefix: prefix)

    :ok
  end

  @spec retry_job(Config.t(), Job.t(), pos_integer()) :: :ok
  def retry_job(%Config{} = conf, %Job{} = job, backoff) do
    %Config{prefix: prefix, repo: repo, log: log} = conf
    %Job{attempt: attempt, id: id, max_attempts: max_attempts} = job

    set =
      if attempt >= max_attempts do
        [state: "discarded", discarded_at: utc_now()]
      else
        [state: "retryable", scheduled_at: next_attempt_at(backoff)]
      end

    updates = [
      set: set,
      push: [errors: %{attempt: attempt, at: utc_now(), error: format_blamed(job.unsaved_error)}]
    ]

    Job
    |> where(id: ^id)
    |> repo.update_all(updates, log: log, prefix: prefix)

    :ok
  end

  @spec notify(Config.t(), binary(), map()) :: :ok
  def notify(%Config{} = conf, channel, %{} = payload) when is_binary(channel) do
    %Config{prefix: prefix, repo: repo, log: log} = conf

    repo.query(
      "SELECT pg_notify($1, $2)",
      ["#{prefix}.#{channel}", Jason.encode!(payload)],
      log: log
    )

    :ok
  end

  @spec acquire_lock?(Config.t(), pos_integer()) :: boolean()
  def acquire_lock?(%Config{prefix: prefix, repo: repo, log: log}, lock_key) do
    case acquire_lock(repo, lock_key, log: log, prefix: prefix) do
      :ok -> true
      {:error, :locked} -> false
    end
  end

  # Helpers

  defp next_attempt_at(backoff), do: DateTime.add(utc_now(), backoff, :second)

  defp format_blamed(%{kind: kind, reason: error, stacktrace: stacktrace}) do
    {blamed, stacktrace} = Exception.blame(kind, error, stacktrace)

    Exception.format(kind, blamed, stacktrace)
  end

  defp insert_unique(%Config{prefix: prefix, repo: repo, log: log}, changeset) do
    query_opts = [log: log, on_conflict: :nothing, prefix: prefix]

    with {:ok, query, lock_key} <- unique_query(changeset),
         :ok <- acquire_lock(repo, lock_key, query_opts),
         {:ok, job} <- unprepared_one(repo, query, query_opts) do
      {:ok, job}
    else
      {:error, :locked} ->
        {:ok, Changeset.apply_changes(changeset)}

      nil ->
        repo.insert(changeset, query_opts)
    end
  end

  defp unique_query(%{changes: %{unique: %{} = unique}} = changeset) do
    %{fields: fields, period: period, states: states} = unique

    fields = for field <- fields, do: {field, Changeset.get_field(changeset, field)}
    states = for state <- states, do: to_string(state)
    lock_key = :erlang.phash2([fields, states])

    query =
      Job
      |> where([j], j.state in ^states)
      |> since_period(period)
      |> where(^fields)
      |> order_by(desc: :id)
      |> limit(1)

    {:ok, query, lock_key}
  end

  defp unique_query(_changeset), do: nil

  defp since_period(query, :infinity), do: query

  defp since_period(query, period) do
    since = DateTime.add(utc_now(), period * -1, :second)

    where(query, [j], j.inserted_at > ^since)
  end

  defp acquire_lock(repo, base_key, opts) do
    pref_key = :erlang.phash2(opts[:prefix])
    lock_key = pref_key + base_key

    case repo.query("SELECT pg_try_advisory_xact_lock($1)", [lock_key], opts) do
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
  defp unprepared_one(repo, query, opts) do
    prefix = Keyword.get(opts, :prefix, "public")

    {raw_sql, bindings} = repo.to_sql(:all, %{query | prefix: prefix})

    case repo.query(raw_sql, bindings, opts) do
      {:ok, %{columns: columns, rows: [rows]}} -> {:ok, repo.load(Job, {columns, rows})}
      _ -> nil
    end
  end
end
