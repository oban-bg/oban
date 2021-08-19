defmodule Oban.Queue.BasicEngine do
  @moduledoc false

  @behaviour Oban.Queue.Engine

  import Ecto.Query
  import DateTime, only: [utc_now: 0]

  alias Ecto.Multi
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
    %Job{attempt: attempt, id: id, max_attempts: max_attempts} = job

    set =
      if attempt >= max_attempts do
        [state: "discarded", discarded_at: utc_now()]
      else
        [state: "retryable", scheduled_at: seconds_from_now(seconds)]
      end

    updates = [
      set: set,
      push: [errors: %{attempt: attempt, at: utc_now(), error: format_blamed(job.unsaved_error)}]
    ]

    Repo.update_all(conf, where(Job, id: ^id), updates)

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
      |> Multi.update_all(:cancelled, cancel_query, [])

    {:ok, %{executing: executing, cancelled: {count, _}}} = Repo.transaction(conf, multi)

    {:ok, {count, executing}}
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

  # Helpers

  defp seconds_from_now(seconds), do: DateTime.add(utc_now(), seconds, :second)

  defp format_blamed(%{kind: kind, reason: error, stacktrace: stacktrace}) do
    {blamed, stacktrace} = Exception.blame(kind, error, stacktrace)

    Exception.format(kind, blamed, stacktrace)
  end
end
