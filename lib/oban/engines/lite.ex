defmodule Oban.Engines.Lite do
  @moduledoc """
  An engine for running Oban with SQLite3.

  ## Usage

  Start an `Oban` instance using the `Lite` engine:

      Oban.start_link(
        engine: Oban.Engines.Lite,
        queues: [default: 10],
        repo: MyApp.Repo
      )
  """

  @behaviour Oban.Engine

  import DateTime, only: [utc_now: 0]
  import Ecto.Query

  alias Ecto.Changeset
  alias Oban.Engines.Basic
  alias Oban.{Config, Engine, Job, Repo}

  @forever 60 * 60 * 24 * 365 * 99

  # EctoSQLite3 doesn't implement `push` for updates, so a json_insert is required.
  defmacrop json_push(column, value) do
    quote do
      fragment("json_insert(?, '$[#]', ?)", unquote(column), unquote(value))
    end
  end

  defmacrop json_contains(column, object) do
    quote do
      fragment(
        """
        SELECT 0 NOT IN (SELECT json_extract(?, '$.' || t.key) = t.value FROM json_each(?) t)
        """,
        unquote(column),
        unquote(object)
      )
    end
  end

  @impl Engine
  defdelegate init(conf, opts), to: Basic

  @impl Engine
  defdelegate put_meta(conf, meta, key, value), to: Basic

  @impl Engine
  defdelegate check_meta(conf, meta, running), to: Basic

  @impl Engine
  defdelegate refresh(conf, meta), to: Basic

  @impl Engine
  defdelegate shutdown(conf, meta), to: Basic

  @impl Engine
  def insert_job(%Config{} = conf, %Changeset{} = changeset, _opts) do
    with {:ok, job} <- fetch_unique(conf, changeset),
         {:ok, job} <- resolve_conflict(conf, job, changeset) do
      {:ok, %Job{job | conflict?: true}}
    else
      :not_found ->
        Repo.insert(conf, changeset)

      error ->
        error
    end
  end

  @impl Engine
  defdelegate insert_all_jobs(conf, changesets, opts), to: Basic

  @impl Engine
  def fetch_jobs(_conf, %{paused: true} = meta, _running) do
    {:ok, {meta, []}}
  end

  def fetch_jobs(_conf, %{limit: limit} = meta, running) when map_size(running) >= limit do
    {:ok, {meta, []}}
  end

  def fetch_jobs(%Config{} = conf, meta, running) do
    demand = meta.limit - map_size(running)

    subset =
      Job
      |> select([:id])
      |> where([j], j.state == "available")
      |> where([j], j.queue == ^meta.queue)
      |> where([j], j.attempt < j.max_attempts)
      |> order_by([j], asc: j.priority, asc: j.scheduled_at, asc: j.id)
      |> limit(^demand)

    updates = [
      set: [state: "executing", attempted_at: utc_now(), attempted_by: [meta.node]],
      inc: [attempt: 1]
    ]

    query =
      Job
      |> where([j], j.id in subquery(subset))
      |> select([j, _], j)

    jobs =
      case Repo.update_all(conf, query, updates) do
        {0, nil} -> []
        {_count, jobs} -> jobs
      end

    {:ok, {meta, jobs}}
  end

  @impl Engine
  def stage_jobs(%Config{} = conf, queryable, opts) do
    limit = Keyword.fetch!(opts, :limit)

    select_query =
      queryable
      |> select([j], map(j, [:id, :queue, :state, :worker]))
      |> where([j], j.state in ~w(scheduled retryable))
      |> where([j], j.scheduled_at <= ^DateTime.utc_now())
      |> limit(^limit)

    staged = Repo.all(conf, select_query)

    if Enum.any?(staged) do
      Repo.update_all(conf, where(Job, [j], j.id in ^Enum.map(staged, & &1.id)),
        set: [state: "available"]
      )
    end

    {:ok, staged}
  end

  @impl Engine
  def prune_jobs(%Config{} = conf, queryable, opts) do
    max_age = Keyword.fetch!(opts, :max_age)
    limit = Keyword.fetch!(opts, :limit)
    time = DateTime.add(DateTime.utc_now(), -max_age)

    select_query =
      queryable
      |> select([j], map(j, [:id, :queue, :state]))
      |> where([j], j.state in ~w(completed cancelled discarded))
      |> where([j], j.scheduled_at < ^time)
      |> limit(^limit)

    pruned = Repo.all(conf, select_query)

    if Enum.any?(pruned) do
      Repo.delete_all(conf, where(Job, [j], j.id in ^Enum.map(pruned, & &1.id)))
    end

    {:ok, pruned}
  end

  @impl Engine
  defdelegate complete_job(conf, job), to: Basic

  @impl Engine
  defdelegate snooze_job(conf, job, seconds), to: Basic

  @impl Engine
  def discard_job(%Config{} = conf, job) do
    query =
      Job
      |> where(id: ^job.id)
      |> update([j],
        set: [
          state: "discarded",
          discarded_at: ^utc_now(),
          errors: json_push(j.errors, ^encode_unsaved(job))
        ]
      )

    Repo.update_all(conf, query, [])

    :ok
  end

  @impl Engine
  def error_job(%Config{} = conf, job, seconds) do
    query =
      Job
      |> where(id: ^job.id)
      |> update([j],
        set: [
          state: "retryable",
          scheduled_at: ^seconds_from_now(seconds),
          errors: json_push(j.errors, ^encode_unsaved(job))
        ]
      )

    Repo.update_all(conf, query, [])

    :ok
  end

  @impl Engine
  def cancel_job(%Config{} = conf, job) do
    query = where(Job, id: ^job.id)

    query =
      if is_map(job.unsaved_error) do
        update(query, [j],
          set: [
            state: "cancelled",
            cancelled_at: ^utc_now(),
            errors: json_push(j.errors, ^encode_unsaved(job))
          ]
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
    base_query = where(queryable, [j], j.state not in ["cancelled", "completed", "discarded"])

    # In SQLite3 an "UPDATE FROM" query returns the final value, not the original from a join. A
    # separate query is needed to get the original state.
    states_map =
      base_query
      |> select([j], {j.id, j.state})
      |> then(&Repo.all(conf, &1))
      |> Map.new()

    query = select(base_query, [j], map(j, [:id, :queue, :state, :worker]))

    jobs =
      conf
      |> Repo.update_all(query, set: [state: "cancelled", cancelled_at: utc_now()])
      |> elem(1)
      |> Enum.map(fn job -> %{job | state: Map.fetch!(states_map, job.id)} end)

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
      |> select([_, x], map(x, [:id, :queue, :state, :worker]))
      |> update([j],
        set: [
          state: "available",
          max_attempts: fragment("MAX(?, ? + 1)", j.max_attempts, j.attempt),
          scheduled_at: ^utc_now(),
          completed_at: nil,
          cancelled_at: nil,
          discarded_at: nil
        ]
      )

    {_, jobs} = Repo.update_all(conf, query, [])

    {:ok, jobs}
  end

  # Insertion

  defp fetch_unique(conf, %{changes: %{unique: %{} = unique}} = changeset) do
    %{fields: fields, keys: keys, period: period, states: states, timestamp: timestamp} = unique

    keys = Enum.map(keys, &to_string/1)
    states = Enum.map(states, &to_string/1)
    since = seconds_from_now(min(period, @forever) * -1)

    dynamic =
      Enum.reduce(fields, true, fn
        field, acc when field in [:args, :meta] ->
          value =
            changeset
            |> Changeset.get_field(field)
            |> map_values(keys)

          cond do
            value == %{} ->
              dynamic([j], field(j, ^field) == ^value and ^acc)

            keys == [] ->
              encoded = Jason.encode!(value)

              dynamic(
                [j],
                json_contains(field(j, ^field), ^encoded) and
                  json_contains(^encoded, field(j, ^field)) and ^acc
              )

            true ->
              dynamic([j], json_contains(field(j, ^field), ^Jason.encode!(value)) and ^acc)
          end

        field, acc ->
          value = Changeset.get_field(changeset, field)

          dynamic([j], field(j, ^field) == ^value and ^acc)
      end)

    query =
      Job
      |> where([j], j.state in ^states)
      |> where([j], fragment("datetime(?) >= datetime(?)", field(j, ^timestamp), ^since))
      |> where(^dynamic)
      |> limit(1)

    case Repo.one(conf, query) do
      nil -> :not_found
      job -> {:ok, job}
    end
  end

  defp fetch_unique(_conf, _changeset), do: :not_found

  defp map_values(value, []), do: value

  defp map_values(value, keys) do
    for {key, val} <- value, str_key = to_string(key), str_key in keys, into: %{} do
      {str_key, val}
    end
  end

  defp resolve_conflict(conf, job, changeset) do
    case Changeset.fetch_change(changeset, :replace) do
      {:ok, replace} ->
        keys = Keyword.get(replace, String.to_existing_atom(job.state), [])

        Repo.update(conf, Changeset.change(job, Map.take(changeset.changes, keys)))

      :error ->
        {:ok, job}
    end
  end

  defp seconds_from_now(seconds), do: DateTime.add(utc_now(), seconds, :second)

  defp encode_unsaved(job) do
    job
    |> Job.format_attempt()
    |> Jason.encode!()
  end
end
