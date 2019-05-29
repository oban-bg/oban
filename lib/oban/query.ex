defmodule Oban.Query do
  @moduledoc false

  import Ecto.Query
  import DateTime, only: [utc_now: 0]

  alias Oban.Job

  @type repo :: module()

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
  defmacrop take_lock(id) do
    quote do
      fragment(
        "pg_try_advisory_lock_shared('oban_jobs'::regclass::oid::int, oban_wrap_id(?))",
        unquote(id)
      )
    end
  end

  # Dropping a lock uses the same format as taking a lock. Only the session that originally took
  # the lock can drop it, but we can't guarantee that the connection used to complete a job was
  # the same connection that fetched the job. Therefore, not all locks will be released
  # immediately after a job is finished. That's ok, as the locks are guaranteed to be released
  # when the connection closes.
  defmacrop drop_lock(id) do
    quote do
      fragment(
        "pg_advisory_unlock_shared('oban_jobs'::regclass::oid::int, oban_wrap_id(?))",
        unquote(id)
      )
    end
  end

  defmacrop no_lock_exists(id) do
    quote do
      fragment(
        """
          NOT EXISTS (
            SELECT 1
            FROM pg_locks
            WHERE locktype = 'advisory'
            AND classid = 'oban_jobs'::regclass::oid::int
            AND objid = oban_wrap_id(?)
          )
        """,
        unquote(id)
      )
    end
  end

  @spec fetch_available_jobs(repo(), binary(), pos_integer()) :: {integer(), nil | [Job.t()]}
  def fetch_available_jobs(repo, queue, demand) do
    subquery =
      Job
      |> where([j], j.state == "available")
      |> where([j], j.queue == ^queue)
      |> where([j], j.scheduled_at <= ^utc_now())
      |> lock("FOR UPDATE SKIP LOCKED")
      |> limit(^demand)
      |> order_by([j], asc: j.scheduled_at, asc: j.id)
      |> select([j], %{id: j.id, lock: take_lock(j.id)})

    query = from(j in Job, join: x in subquery(subquery), on: j.id == x.id, select: j)

    repo.update_all(
      query,
      set: [state: "executing", attempted_at: utc_now()],
      inc: [attempt: 1]
    )
  end

  @spec stage_scheduled_jobs(repo(), binary()) :: {integer(), nil}
  def stage_scheduled_jobs(repo, queue) do
    Job
    |> where([j], j.state in ["scheduled", "retryable"])
    |> where([j], j.queue == ^queue)
    |> where([j], j.scheduled_at <= ^utc_now())
    |> repo.update_all(set: [state: "available"])
  end

  @spec rescue_orphaned_jobs(repo(), binary()) :: {integer(), nil}
  def rescue_orphaned_jobs(repo, queue) do
    Job
    |> where([j], j.state == "executing")
    |> where([j], j.queue == ^queue)
    |> where([j], no_lock_exists(j.id))
    |> repo.update_all(set: [state: "available"])
  end

  @spec delete_truncated_jobs(repo(), pos_integer()) :: {integer(), nil}
  def delete_truncated_jobs(repo, limit) do
    subquery =
      Job
      |> where([j], j.state in ["completed", "discarded"])
      |> offset(^limit)
      |> order_by(desc: :id)

    repo.delete_all(from(j in Job, join: x in subquery(subquery), on: j.id == x.id))
  end

  @spec delete_outdated_jobs(repo(), pos_integer()) :: {integer(), nil}
  def delete_outdated_jobs(repo, seconds) do
    outdated_at = DateTime.add(utc_now(), -seconds)

    Job
    |> where([j], j.state == "completed" and j.completed_at < ^outdated_at)
    |> or_where([j], j.state == "discarded" and j.attempted_at < ^outdated_at)
    |> repo.delete_all()
  end

  @spec complete_job(repo(), Job.t()) :: :ok
  def complete_job(repo, %Job{id: id}) do
    repo.update_all(select_for_update(id), set: [state: "completed", completed_at: utc_now()])

    :ok
  end

  @spec discard_job(repo(), Job.t()) :: :ok
  def discard_job(repo, %Job{id: id}) do
    repo.update_all(select_for_update(id), set: [state: "discarded", completed_at: utc_now()])

    :ok
  end

  @spec retry_job(repo(), Job.t(), binary()) :: :ok
  def retry_job(repo, %Job{} = job, formatted_error) do
    %Job{attempt: attempt, id: id, max_attempts: max_attempts} = job

    updates =
      if attempt >= max_attempts do
        [state: "discarded", completed_at: utc_now()]
      else
        [state: "retryable", completed_at: utc_now(), scheduled_at: next_attempt_at(attempt)]
      end

    repo.update_all(
      select_for_update(id),
      set: updates,
      push: [errors: %{attempt: attempt, at: utc_now(), error: formatted_error}]
    )
  end

  # Helpers

  defp next_attempt_at(attempt, base_offset \\ 15) do
    offset = trunc(:math.pow(attempt, 4) + base_offset)

    NaiveDateTime.add(utc_now(), offset, :second)
  end

  defp select_for_update(id) do
    Job
    |> where(id: ^id)
    |> select(%{lock: drop_lock(^id)})
  end
end
