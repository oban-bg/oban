defmodule Oban.Query do
  @moduledoc false

  import Ecto.Query
  import NaiveDateTime, only: [utc_now: 0]

  alias Oban.Job

  @spec fetch_available_jobs(module(), binary(), pos_integer()) :: {integer(), nil | [Job.t()]}
  def fetch_available_jobs(repo, queue, demand) do
    subquery =
      Job
      |> where([job], job.state == "available")
      |> where([job], job.queue == ^queue)
      |> where([job], job.scheduled_at <= ^utc_now())
      |> lock("FOR UPDATE SKIP LOCKED")
      |> limit(^demand)
      |> order_by([job], asc: job.scheduled_at, asc: job.id)
      |> select([:id])

    query = from(job in Job, join: x in subquery(subquery), on: job.id == x.id, select: job)

    repo.update_all(
      query,
      set: [state: "executing", attempted_at: utc_now()],
      inc: [attempt: 1]
    )
  end

  @spec complete_job(module(), Job.t()) :: :ok
  def complete_job(repo, %Job{id: id}) do
    _ = repo.update_all(where(Job, id: ^id), set: [state: "completed"])

    :ok
  end

  @spec retry_job(module(), Job.t()) :: :ok
  def retry_job(repo, %Job{attempt: attempt, id: id, max_attempts: max_attempts}) do
    updates =
      if attempt >= max_attempts do
        [state: "discarded"]
      else
        [state: "available", scheduled_at: next_attempt_at(attempt)]
      end

    repo.update_all(where(Job, id: ^id), set: updates)
  end

  @spec next_attempt_at(pos_integer(), pos_integer()) :: NaiveDateTime.t()
  def next_attempt_at(attempt, base_offset \\ 15) do
    offset = trunc(:math.pow(attempt, 5) + base_offset)

    NaiveDateTime.add(utc_now(), offset, :second)
  end
end
