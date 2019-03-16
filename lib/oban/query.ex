defmodule Oban.Query do
  @moduledoc false

  import Ecto.Query
  import DateTime, only: [utc_now: 0]

  alias Oban.Job

  # Taking a shared lock this way will always work, even if a lock has been taken by another
  # connection.
  defmacrop take_lock(id) do
    quote do
      fragment("pg_try_advisory_lock_shared(?)", unquote(id))
    end
  end

  # Dropping a lock uses the same format as taking a lock. Only the session that originally took
  # the lock can drop it, but we can't guarantee that the connection used to complete a job was
  # the same connection that fetched the job. Therefore, not all locks will be released
  # immediately after a job is finished. That's ok, as the locks are guaranteed to be released
  # when the connection closes.
  defmacrop drop_lock(id) do
    quote do
      fragment("pg_advisory_unlock_shared(?)", unquote(id))
    end
  end

  @spec fetch_available_jobs(module(), binary(), pos_integer()) :: {integer(), nil | [Job.t()]}
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

  @spec rescue_orphaned_jobs(module(), binary()) :: {integer(), nil}
  def rescue_orphaned_jobs(repo, queue) do
    Job
    |> where([j], j.state == "executing")
    |> where([j], j.queue == ^queue)
    |> where([j], j.id not in fragment("SELECT objid FROM pg_locks WHERE locktype = 'advisory'"))
    |> repo.update_all(set: [state: "available"])
  end

  @spec delete_truncated_jobs(module(), pos_integer()) :: {integer(), nil}
  def delete_truncated_jobs(repo, limit) do
    subquery =
      Job
      |> where([j], j.state in ["completed", "discarded"])
      |> offset(^limit)
      |> order_by(desc: :id)

    repo.delete_all(from(j in Job, join: x in subquery(subquery), on: j.id == x.id))
  end

  @spec delete_outdated_jobs(module(), pos_integer()) :: {integer(), nil}
  def delete_outdated_jobs(repo, seconds) do
    outdated_at = DateTime.add(utc_now(), -seconds)

    Job
    |> where([j], j.state == "completed" and j.completed_at < ^outdated_at)
    |> or_where([j], j.state == "discarded" and j.attempted_at < ^outdated_at)
    |> repo.delete_all()
  end

  @spec complete_job(module(), Job.t()) :: :ok
  def complete_job(repo, %Job{id: id}) do
    repo.update_all(select_for_update(id), set: [state: "completed", completed_at: utc_now()])

    :ok
  end

  @spec retry_job(module(), Job.t(), binary()) :: :ok
  def retry_job(repo, %Job{} = job, formatted_error) do
    %Job{attempt: attempt, id: id, max_attempts: max_attempts} = job

    updates =
      if attempt >= max_attempts do
        [state: "discarded", completed_at: utc_now()]
      else
        [state: "available", completed_at: utc_now(), scheduled_at: next_attempt_at(attempt)]
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
