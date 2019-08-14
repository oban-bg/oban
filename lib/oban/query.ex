defmodule Oban.Query do
  @moduledoc false

  import Ecto.Query
  import DateTime, only: [utc_now: 0]

  alias Ecto.{Changeset, Multi}
  alias Oban.{Config, Job}

  # Taking a shared lock this way will always work, even if a lock has been taken by another
  # connection.
  #
  # Locks use the `oid` of the `oban_jobs` table to provide a consistent and virtually unique
  # namespace. Using two `int` values instead of a single `bigint` ensures that we only have a 1
  # in 2^31 - 1 chance of colliding with locks from application code.
  #
  # Due to the switch from `bigint` to `int` we also need to wrap `bigint` values to less than the
  # maximum integer value. This is handled by the immutable `oban_wrap_id` function directly in
  # Postgres.
  #
  defmacrop take_lock(ns, id) do
    quote do
      fragment("pg_try_advisory_lock_shared(?, oban_wrap_id(?))", unquote(ns), unquote(id))
    end
  end

  defmacrop no_lock_exists(ns, id) do
    quote do
      fragment(
        """
          NOT EXISTS (
            SELECT 1
            FROM pg_locks
            WHERE locktype = 'advisory'
              AND classid = ?
              AND objid = oban_wrap_id(?)
          )
        """,
        unquote(ns),
        unquote(id)
      )
    end
  end

  @spec fetch_available_jobs(Config.t(), binary(), pos_integer()) :: {integer(), nil | [Job.t()]}
  def fetch_available_jobs(%Config{prefix: prefix, repo: repo, verbose: verbose}, queue, demand) do
    subquery =
      Job
      |> where([j], j.state == "available")
      |> where([j], j.queue == ^queue)
      |> where([j], j.scheduled_at <= ^utc_now())
      |> lock("FOR UPDATE SKIP LOCKED")
      |> limit(^demand)
      |> order_by([j], asc: j.scheduled_at, asc: j.id)
      |> select([j], %{id: j.id, lock: take_lock(^to_ns(prefix), j.id)})

    query =
      from(
        j in Job,
        join: x in subquery(subquery, prefix: prefix),
        on: j.id == x.id,
        select: j
      )

    updates = [
      set: [state: "executing", attempted_at: utc_now()],
      inc: [attempt: 1]
    ]

    repo.update_all(query, updates, log: verbose, prefix: prefix)
  end

  @spec fetch_or_insert_job(Config.t(), Changeset.t()) :: {:ok, Job.t()} | {:error, Changeset.t()}
  def fetch_or_insert_job(%Config{prefix: prefix, repo: repo, verbose: verbose}, changeset) do
    case get_unique_job(repo, prefix, changeset) do
      %Job{} = job -> {:ok, job}
      nil -> repo.insert(changeset, log: verbose, on_conflict: :nothing, prefix: prefix)
    end
  end

  @spec fetch_or_insert_job(Config.t(), Multi.t(), atom(), Changeset.t()) :: Multi.t()
  def fetch_or_insert_job(config, multi, name, changeset) do
    Multi.run(multi, name, fn repo, _changes ->
      fetch_or_insert_job(%{config | repo: repo}, changeset)
    end)
  end

  # Only the session that originally took the lock can drop it, but we can't guarantee that the
  # current connection is the same connection that started a job. Therefore, some locks may not
  # be released by the current connection. Unlocking in batches ensures that all locks have a
  # chance of being released _eventually_.
  @unlock_query """
  SELECT u.id
  FROM (
    SELECT x AS id, pg_advisory_unlock_shared($1::int, x) AS unlocked
    FROM unnest($2::int[]) AS a(x)
  ) AS u WHERE u.unlocked = true
  """
  @spec unlock_jobs(Config.t(), [integer()]) :: [integer()]
  def unlock_jobs(%Config{prefix: prefix, repo: repo, verbose: verbose}, unlockable) do
    case repo.query!(@unlock_query, [to_ns(prefix), unlockable], log: verbose) do
      %{rows: [rows]} -> rows
      _ -> []
    end
  end

  @spec stage_scheduled_jobs(Config.t(), binary()) :: {integer(), nil}
  def stage_scheduled_jobs(%Config{prefix: prefix, repo: repo, verbose: verbose}, queue) do
    Job
    |> where([j], j.state in ["scheduled", "retryable"])
    |> where([j], j.queue == ^queue)
    |> where([j], j.scheduled_at <= ^utc_now())
    |> repo.update_all([set: [state: "available"]], log: verbose, prefix: prefix)
  end

  @spec rescue_orphaned_jobs(Config.t(), binary()) :: {integer(), nil}
  def rescue_orphaned_jobs(%Config{prefix: prefix, repo: repo, verbose: verbose}, queue) do
    Job
    |> where([j], j.state == "executing")
    |> where([j], j.queue == ^queue)
    |> where([j], no_lock_exists(^to_ns(prefix), j.id))
    |> repo.update_all([set: [state: "available"]], log: verbose, prefix: prefix)
  end

  @spec delete_truncated_jobs(Config.t(), pos_integer(), pos_integer()) :: {integer(), nil}
  def delete_truncated_jobs(%Config{prefix: prefix, repo: repo, verbose: verbose}, length, limit) do
    subquery =
      Job
      |> where([j], j.state in ["completed", "discarded"])
      |> offset(^length)
      |> limit(^limit)
      |> order_by(desc: :id)

    query = from(j in Job, join: x in subquery(subquery, prefix: prefix), on: j.id == x.id)

    repo.delete_all(query, log: verbose, prefix: prefix)
  end

  @spec delete_outdated_jobs(Config.t(), pos_integer(), pos_integer()) :: {integer(), nil}
  def delete_outdated_jobs(%Config{prefix: prefix, repo: repo, verbose: verbose}, seconds, limit) do
    outdated_at = DateTime.add(utc_now(), -seconds)

    subquery =
      Job
      |> where([j], j.state == "completed" and j.completed_at < ^outdated_at)
      |> or_where([j], j.state == "discarded" and j.attempted_at < ^outdated_at)
      |> limit(^limit)
      |> order_by(desc: :id)

    query = from(j in Job, join: x in subquery(subquery, prefix: prefix), on: j.id == x.id)

    repo.delete_all(query, log: verbose, prefix: prefix)
  end

  @spec complete_job(Config.t(), Job.t()) :: :ok
  def complete_job(%Config{prefix: prefix, repo: repo, verbose: verbose}, %Job{id: id}) do
    repo.update_all(
      where(Job, id: ^id),
      [set: [state: "completed", completed_at: utc_now()]],
      log: verbose,
      prefix: prefix
    )

    :ok
  end

  @spec discard_job(Config.t(), Job.t()) :: :ok
  def discard_job(%Config{prefix: prefix, repo: repo, verbose: verbose}, %Job{id: id}) do
    repo.update_all(
      where(Job, id: ^id),
      [set: [state: "discarded", completed_at: utc_now()]],
      log: verbose,
      prefix: prefix
    )

    :ok
  end

  @spec retry_job(Config.t(), Job.t(), pos_integer(), binary()) :: :ok
  def retry_job(%Config{repo: repo} = config, %Job{} = job, backoff, formatted_error) do
    %Job{attempt: attempt, id: id, max_attempts: max_attempts} = job

    set =
      if attempt >= max_attempts do
        [state: "discarded", completed_at: utc_now()]
      else
        [state: "retryable", completed_at: utc_now(), scheduled_at: next_attempt_at(backoff)]
      end

    updates = [
      set: set,
      push: [errors: %{attempt: attempt, at: utc_now(), error: formatted_error}]
    ]

    repo.update_all(
      where(Job, id: ^id),
      updates,
      log: config.verbose,
      prefix: config.prefix
    )
  end

  @spec notify(Config.t(), binary(), binary()) :: :ok
  def notify(%Config{prefix: prefix, repo: repo, verbose: verbose}, channel, payload)
      when is_binary(channel) and is_binary(payload) do
    repo.query("SELECT pg_notify($1, $2)", ["#{prefix}.#{channel}", payload], log: verbose)

    :ok
  end

  @spec to_ns(value :: binary()) :: pos_integer()
  def to_ns(value \\ "public"), do: :erlang.phash2(value)

  # Helpers

  defp next_attempt_at(backoff), do: DateTime.add(utc_now(), backoff, :second)

  defp get_unique_job(repo, prefix, %{changes: %{unique: unique} = changes})
       when is_map(unique) do
    %{fields: fields, period: period, states: states} = unique

    since = DateTime.add(utc_now(), period * -1, :second)
    fields = for field <- fields, do: {field, Map.get(changes, field)}
    states = for state <- states, do: to_string(state)

    Job
    |> where([j], j.state in ^states)
    |> where([j], j.inserted_at > ^since)
    |> where(^fields)
    |> order_by(desc: :id)
    |> limit(1)
    |> repo.one(prefix: prefix)
  end

  defp get_unique_job(_repo, _prefix, _changeset), do: nil
end
