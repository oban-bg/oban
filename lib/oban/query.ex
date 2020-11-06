defmodule Oban.Query do
  @moduledoc false

  import Ecto.Query
  import DateTime, only: [utc_now: 0]

  alias Ecto.{Changeset, Multi}
  alias Oban.{Config, Job, Repo}

  @spec fetch_available_jobs(Config.t(), binary(), binary(), pos_integer()) :: {:ok, [Job.t()]}
  def fetch_available_jobs(%Config{node: node} = conf, queue, nonce, demand) do
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

    Repo.transaction(
      conf,
      fn ->
        query =
          Job
          |> where([j], j.id in subquery(subset))
          |> select([j, _], j)

        case Repo.update_all(conf, query, updates) do
          {0, nil} -> []
          {_count, jobs} -> jobs
        end
      end
    )
  end

  @spec fetch_or_insert_job(Config.t(), Changeset.t()) :: {:ok, Job.t()} | {:error, term()}
  def fetch_or_insert_job(conf, changeset) do
    fun = fn -> insert_unique(conf, changeset) end
    with {:ok, result} <- Repo.transaction(conf, fun), do: result
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
    entries = Enum.map(changesets, &Job.to_map/1)

    case Repo.insert_all(conf, Job, entries, on_conflict: :nothing, returning: true) do
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

  @spec stage_scheduled_jobs(Config.t(), binary(), opts :: keyword()) :: {:ok, {integer(), nil}}
  def stage_scheduled_jobs(%Config{} = conf, queue, opts \\ []) do
    max_scheduled_at = Keyword.get(opts, :max_scheduled_at, utc_now())

    subset =
      Job
      |> select([j], j.id)
      |> where([j], j.state in ["scheduled", "retryable"])
      |> where([j], j.queue == ^queue)
      |> where([j], j.scheduled_at <= ^max_scheduled_at)
      |> lock("FOR UPDATE SKIP LOCKED")

    Repo.transaction(
      conf,
      fn ->
        Repo.update_all(conf, where(Job, [j], j.id in subquery(subset)), set: [state: "available"])
      end
    )
  end

  @spec complete_job(Config.t(), Job.t()) :: :ok
  def complete_job(%Config{} = conf, %Job{id: id}) do
    Repo.update_all(
      conf,
      where(Job, id: ^id),
      set: [state: "completed", completed_at: utc_now()]
    )

    :ok
  end

  @spec discard_job(Config.t(), Job.t()) :: :ok
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

  @cancellable_states ~w(available scheduled retryable)

  @spec cancel_job(Config.t(), pos_integer() | Job.t()) :: :ok | :ignored
  def cancel_job(%Config{} = conf, %Job{id: id}) do
    updates = [set: [state: "cancelled", cancelled_at: utc_now()]]

    Repo.update_all(conf, where(Job, id: ^id), updates)

    :ok
  end

  def cancel_job(%Config{} = conf, job_id) do
    query = where(Job, [j], j.id == ^job_id and j.state in @cancellable_states)
    updates = [set: [state: "cancelled", cancelled_at: utc_now()]]

    case Repo.update_all(conf, query, updates) do
      {1, nil} -> :ok
      {0, nil} -> :ignored
    end
  end

  @spec snooze_job(Config.t(), Job.t(), pos_integer()) :: :ok
  def snooze_job(%Config{} = conf, %Job{id: id}, seconds) do
    scheduled_at = DateTime.add(utc_now(), seconds)

    updates = [
      set: [state: "scheduled", scheduled_at: scheduled_at],
      inc: [max_attempts: 1]
    ]

    Repo.update_all(conf, where(Job, id: ^id), updates)
    :ok
  end

  @spec retry_job(Config.t(), pos_integer()) :: :ok
  def retry_job(conf, id) do
    query =
      Job
      |> where([j], j.id == ^id)
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

    Repo.update_all(conf, query, [])

    :ok
  end

  @spec retry_job(Config.t(), Job.t(), pos_integer()) :: :ok
  def retry_job(%Config{} = conf, %Job{} = job, backoff) do
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

    Repo.update_all(conf, where(Job, id: ^id), updates)
    :ok
  end

  @spec notify(Config.t(), binary(), map()) :: :ok
  def notify(%Config{prefix: prefix} = conf, channel, %{} = payload) when is_binary(channel) do
    Repo.query(
      conf,
      "SELECT pg_notify($1, $2)",
      ["#{prefix}.#{channel}", Jason.encode!(payload)]
    )

    :ok
  end

  @spec acquire_lock?(Config.t(), pos_integer()) :: boolean()
  def acquire_lock?(%Config{} = conf, lock_key) do
    case acquire_lock(conf, lock_key) do
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

  defp insert_unique(%Config{} = conf, changeset) do
    query_opts = [on_conflict: :nothing]

    with {:ok, query, lock_key} <- unique_query(changeset),
         :ok <- acquire_lock(conf, lock_key, query_opts),
         {:ok, job} <- unprepared_one(conf, query, query_opts) do
      return_or_replace(conf, query_opts, job, changeset)
    else
      {:error, :locked} ->
        {:ok, Changeset.apply_changes(changeset)}

      nil ->
        Repo.insert(conf, changeset, query_opts)
    end
  end

  defp return_or_replace(conf, query_opts, job, changeset) do
    if Changeset.get_change(changeset, :replace_args) do
      Repo.update(
        conf,
        Ecto.Changeset.change(job, %{args: changeset.changes.args}),
        query_opts
      )
    else
      {:ok, job}
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

  defp unique_field({changeset, :args, [_ | _] = keys}, acc) do
    args =
      changeset
      |> Changeset.get_field(:args)
      |> Map.new(fn {key, val} -> {to_string(key), val} end)
      |> Map.take(keys)

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
