defmodule Oban.Query do
  @moduledoc false

  import Ecto.Query
  import DateTime, only: [utc_now: 0]

  alias Ecto.{Changeset, Multi}
  alias Oban.{Beat, Config, Job}

  @spec fetch_available_jobs(Config.t(), binary(), binary(), pos_integer()) ::
          {integer(), nil | [Job.t()]}
  def fetch_available_jobs(%Config{} = conf, queue, nonce, demand) do
    %Config{node: node, prefix: prefix, repo: repo, verbose: verbose} = conf

    subquery =
      Job
      |> where([j], j.state == "available")
      |> where([j], j.queue == ^queue)
      |> lock("FOR UPDATE SKIP LOCKED")
      |> limit(^demand)
      |> order_by([j], asc: j.scheduled_at, asc: j.id)
      |> select([:id])

    updates = [
      set: [state: "executing", attempted_at: utc_now(), attempted_by: [node, queue, nonce]],
      inc: [attempt: 1]
    ]

    Job
    |> join(:inner, [j], x in subquery(subquery, prefix: prefix), on: j.id == x.id)
    |> select([j, _], j)
    |> repo.update_all(updates, log: verbose, prefix: prefix)
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

  @spec stage_scheduled_jobs(Config.t(), binary()) :: {integer(), nil}
  def stage_scheduled_jobs(%Config{prefix: prefix, repo: repo, verbose: verbose}, queue) do
    Job
    |> where([j], j.state in ["scheduled", "retryable"])
    |> where([j], j.queue == ^queue)
    |> where([j], j.scheduled_at <= ^utc_now())
    |> repo.update_all([set: [state: "available"]], log: verbose, prefix: prefix)
  end

  @spec insert_beat(Config.t(), map()) :: {:ok, Beat.t()} | {:error, Changeset.t()}
  def insert_beat(%Config{prefix: prefix, repo: repo, verbose: verbose}, params) do
    params
    |> Beat.new()
    |> repo.insert(log: verbose, prefix: prefix)
  end

  @doc """
  Finds all executing jobs within a queue which were attempted by a producer that hasn't had a
  pulse recently.
  """
  @spec rescue_orphaned_jobs(Config.t(), binary()) :: {integer(), nil}
  def rescue_orphaned_jobs(%Config{} = conf, queue) do
    %Config{prefix: prefix, repo: repo, rescue_after: seconds, verbose: verbose} = conf

    orphaned_at = DateTime.add(utc_now(), -seconds)

    subquery =
      Job
      |> where([j], j.state == "executing" and j.queue == ^queue)
      |> join(:left, [j], b in Beat,
        on: j.attempted_by == [b.node, b.queue, b.nonce] and b.inserted_at > ^orphaned_at
      )
      |> where([_, b], is_nil(b.node))
      |> select([:id])

    Job
    |> join(:inner, [j], x in subquery(subquery, prefix: prefix), on: j.id == x.id)
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

    Job
    |> join(:inner, [j], x in subquery(subquery, prefix: prefix), on: j.id == x.id)
    |> repo.delete_all(log: verbose, prefix: prefix)
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

    Job
    |> join(:inner, [j], x in subquery(subquery, prefix: prefix), on: j.id == x.id)
    |> repo.delete_all(log: verbose, prefix: prefix)
  end

  @spec delete_outdated_beats(Config.t(), pos_integer()) :: {integer(), nil}
  def delete_outdated_beats(%Config{prefix: prefix, repo: repo, verbose: verbose}, seconds) do
    outdated_at = DateTime.add(utc_now(), -seconds)

    Beat
    |> where([b], b.inserted_at < ^outdated_at)
    |> repo.delete_all(log: verbose, prefix: prefix)
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

  # Helpers

  defp next_attempt_at(backoff), do: DateTime.add(utc_now(), backoff, :second)

  defp get_unique_job(repo, prefix, %{changes: %{unique: unique}} = changeset)
       when is_map(unique) do
    %{fields: fields, period: period, states: states} = unique

    since = DateTime.add(utc_now(), period * -1, :second)
    fields = for field <- fields, do: {field, Changeset.get_field(changeset, field)}
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
