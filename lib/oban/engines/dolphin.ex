defmodule Oban.Engines.Dolphin do
  @moduledoc """
  An engine for running Oban with MySQL (via the MyXQL adapter).

  ## Usage

  Start an `Oban` instance using the `Dolphin` engine:

      Oban.start_link(
        engine: Oban.Engines.Dolphin,
        queues: [default: 10],
        repo: MyApp.Repo
      )
  """

  @behaviour Oban.Engine

  import DateTime, only: [utc_now: 0]
  import Ecto.Query

  alias Ecto.Changeset
  alias Oban.{Config, Engine, Job, Repo}
  alias Oban.Engines.Basic

  defmacrop json_push(column, value) do
    quote do
      fragment("json_array_append(?, '$', ?)", unquote(column), unquote(value))
    end
  end

  defmacrop json_contains(column, object) do
    quote do
      fragment("json_contains(?, ?)", unquote(column), unquote(object))
    end
  end

  @forever 60 * 60 * 24 * 365 * 99

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
  def insert_job(%Config{} = conf, %Changeset{} = changeset, opts) do
    with {:ok, job} <- fetch_unique(conf, changeset, opts),
         {:ok, job} <- resolve_conflict(conf, job, changeset, opts) do
      {:ok, %{job | conflict?: true}}
    else
      :not_found ->
        Repo.insert(conf, changeset)

      error ->
        error
    end
  end

  @impl Engine
  def insert_all_jobs(%Config{} = conf, changesets, opts) do
    jobs = Enum.map(changesets, &Job.to_map/1)

    {_count, _jobs} = Repo.insert_all(conf, Job, jobs, opts)

    Enum.map(changesets, &Ecto.Changeset.apply_action!(&1, :insert))
  end

  @impl Engine
  def fetch_jobs(_conf, %{paused: true} = meta, _running) do
    {:ok, {meta, []}}
  end

  def fetch_jobs(_conf, %{limit: limit} = meta, running) when map_size(running) >= limit do
    {:ok, {meta, []}}
  end

  def fetch_jobs(%Config{} = conf, meta, running) do
    demand = meta.limit - map_size(running)

    query = """
    SELECT *
    FROM oban_jobs
    WHERE state = 'available' AND queue = '#{meta.queue}' AND attempt < max_attempts
    ORDER BY priority, scheduled_at, id
    LIMIT #{demand}
    FOR UPDATE SKIP LOCKED
    """

    {:ok, jobs} =
      Repo.transaction(conf, fn ->
        # Using literal SQL allows us to use `query_type: text`, which is required in environments
        # such as Planetscale where the binary protocol is incompatible with prepared statements.
        %{columns: columns, rows: rows} = Repo.query!(conf, query, [], query_type: :text)

        jobs = Enum.map(rows, &conf.repo.load(Job, {columns, &1}))
        at = utc_now()
        by = [meta.node, meta.uuid]

        updates = [
          set: [state: "executing", attempted_at: at, attempted_by: by],
          inc: [attempt: 1]
        ]

        # MySQL doesn't support selecting in an update. To accomplish the required functionality
        # we have to select, then update.
        Repo.update_all(conf, where(Job, [j], j.id in ^Enum.map(jobs, & &1.id)), updates)

        Enum.map(
          jobs,
          &%{&1 | attempt: &1.attempt + 1, attempted_at: at, attempted_by: by, state: "executing"}
        )
      end)

    {:ok, {meta, jobs}}
  end

  @impl Engine
  def stage_jobs(%Config{} = conf, queryable, opts) do
    limit = Keyword.fetch!(opts, :limit)

    select_query =
      queryable
      |> select([j], map(j, [:id, :queue, :state, :worker]))
      |> where([j], j.state in ~w(scheduled retryable))
      |> where([j], j.scheduled_at <= ^utc_now())
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
    time = DateTime.add(utc_now(), -max_age)

    select_query =
      queryable
      |> select([j], map(j, [:id, :queue, :state]))
      |> where([j], j.state == "completed" and j.scheduled_at < ^time)
      |> or_where([j], j.state == "cancelled" and j.cancelled_at < ^time)
      |> or_where([j], j.state == "discarded" and j.discarded_at < ^time)
      |> limit(^limit)

    pruned = Repo.all(conf, select_query)

    Repo.delete_all(conf, where(queryable, [j], j.id in ^Enum.map(pruned, & &1.id)))

    {:ok, pruned}
  end

  @impl Engine
  def rescue_jobs(%Config{} = conf, queryable, opts) do
    rescue_after = Keyword.fetch!(opts, :rescue_after)

    now = DateTime.utc_now()
    cut = DateTime.add(now, -rescue_after, :millisecond)

    select_query =
      queryable
      |> where([j], j.state == "executing" and j.attempted_at < ^cut)
      |> select([j], map(j, [:attempt, :id, :max_attempts, :queue]))

    {available, discarded} =
      conf
      |> Repo.all(select_query)
      |> Enum.reduce({[], []}, fn job, {res_acc, dis_acc} ->
        if job.attempt < job.max_attempts do
          {[Map.put(job, :state, "available") | res_acc], dis_acc}
        else
          {res_acc, [Map.put(job, :state, "discarded") | dis_acc]}
        end
      end)

    to_where = fn jobs -> where(queryable, [j], j.id in ^Enum.map(jobs, & &1.id)) end

    Repo.update_all(conf, to_where.(available), set: [state: "available"])
    Repo.update_all(conf, to_where.(discarded), set: [state: "discarded", discarded_at: now])

    {:ok, available ++ discarded}
  end

  @impl Engine
  defdelegate complete_job(conf, job), to: Basic

  @impl Engine
  def discard_job(%Config{} = conf, job) do
    query =
      Job
      |> where(id: ^job.id)
      |> update([j],
        set: [
          state: "discarded",
          discarded_at: ^utc_now(),
          errors: json_push(j.errors, ^Job.format_attempt(job))
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
          errors: json_push(j.errors, ^Job.format_attempt(job))
        ]
      )

    Repo.update_all(conf, query, [])

    :ok
  end

  @impl Engine
  defdelegate snooze_job(conf, job, seconds), to: Basic

  @impl Engine
  def cancel_job(%Config{} = conf, job) do
    query = where(Job, id: ^job.id)

    query =
      if is_map(job.unsaved_error) do
        update(query, [j],
          set: [
            state: "cancelled",
            cancelled_at: ^utc_now(),
            errors: json_push(j.errors, ^Job.format_attempt(job))
          ]
        )
      else
        query
        |> where([j], j.state not in ~w(cancelled completed discarded))
        |> update(set: [state: "cancelled", cancelled_at: ^utc_now()])
      end

    Repo.update_all(conf, query, [])

    :ok
  end

  @impl Engine
  def cancel_all_jobs(%Config{} = conf, queryable) do
    Repo.transaction(conf, fn ->
      jobs =
        queryable
        |> where([j], j.state not in ~w(cancelled completed discarded))
        |> select([j], map(j, [:id, :queue, :state]))
        |> then(&Repo.all(conf, &1))

      query = where(Job, [j], j.id in ^Enum.map(jobs, & &1.id))

      Repo.update_all(conf, query, set: [state: "cancelled", cancelled_at: utc_now()])

      jobs
    end)
  end

  @impl Engine
  def delete_job(%Config{} = conf, %Job{id: id}) do
    delete_all_jobs(conf, where(Job, [j], j.id == ^id))

    :ok
  end

  @impl Engine
  def delete_all_jobs(%Config{} = conf, queryable) do
    select_query =
      queryable
      |> select([j], map(j, [:id, :queue, :state]))
      |> where([j], j.state != "executing")

    deleted = Repo.all(conf, select_query)

    if Enum.any?(deleted) do
      Repo.delete_all(conf, where(Job, [j], j.id in ^Enum.map(deleted, & &1.id)))
    end

    {:ok, deleted}
  end

  @impl Engine
  def retry_job(%Config{} = conf, %Job{id: id}) do
    retry_all_jobs(conf, where(Job, [j], j.id == ^id))

    :ok
  end

  @impl Engine
  def retry_all_jobs(%Config{} = conf, queryable) do
    Repo.transaction(conf, fn ->
      query =
        queryable
        |> where([j], j.state not in ~w(available executing))
        |> select([j], map(j, [:id, :queue, :state]))

      jobs = Repo.all(conf, query)

      update_query =
        Job
        |> where([j], j.id in ^Enum.map(jobs, & &1.id))
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

      Repo.update_all(conf, update_query, [])

      Enum.map(jobs, &%{&1 | state: "available"})
    end)
  end

  @impl Engine
  defdelegate update_job(conf, job, changes), to: Basic

  # Insertion

  defp fetch_unique(conf, %{changes: %{unique: %{} = unique}} = changeset, opts) do
    %{fields: fields, keys: keys, period: period, states: states, timestamp: timestamp} = unique

    states = Enum.map(states, &to_string/1)
    since = seconds_from_now(min(period, @forever) * -1)

    dynamic =
      Enum.reduce(fields, true, fn
        field, acc when field in [:args, :meta] ->
          keys = Enum.map(keys, &to_string/1)
          value = map_values(changeset, field, keys)

          cond do
            value == %{} ->
              dynamic([j], json_contains(^value, field(j, ^field)) and ^acc)

            keys == [] ->
              dynamic(
                [j],
                json_contains(field(j, ^field), ^value) and
                  json_contains(^value, field(j, ^field)) and ^acc
              )

            true ->
              dynamic([j], json_contains(field(j, ^field), ^value) and ^acc)
          end

        field, acc ->
          value = Changeset.get_field(changeset, field)

          dynamic([j], field(j, ^field) == ^value and ^acc)
      end)

    query =
      Job
      |> where([j], j.state in ^states)
      |> where([j], fragment("? >= ?", field(j, ^timestamp), ^since))
      |> where(^dynamic)
      |> limit(1)

    case Repo.one(conf, query, opts) do
      nil -> :not_found
      job -> {:ok, job}
    end
  end

  defp fetch_unique(_conf, _changeset, _opts), do: :not_found

  defp resolve_conflict(conf, job, changeset, opts) do
    case Changeset.fetch_change(changeset, :replace) do
      {:ok, replace} ->
        keys = Keyword.get(replace, String.to_existing_atom(job.state), [])

        Repo.update(
          conf,
          Changeset.change(job, Map.take(changeset.changes, keys)),
          opts
        )

      :error ->
        {:ok, job}
    end
  end

  defp map_values(changeset, field, keys) do
    case keys do
      [] ->
        Changeset.get_field(changeset, field)

      [_ | _] ->
        changeset
        |> Changeset.get_field(field)
        |> Map.new(fn {key, val} -> {to_string(key), val} end)
        |> Map.take(keys)
    end
  end

  defp seconds_from_now(seconds), do: DateTime.add(utc_now(), seconds, :second)
end
