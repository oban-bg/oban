defmodule Oban.Queue.InlineEngine do
  @moduledoc false

  @behaviour Oban.Queue.Engine

  import DateTime, only: [utc_now: 0]

  alias Ecto.{Changeset, Multi}
  alias Oban.{Config, Job}
  alias Oban.Queue.{BasicEngine, Engine, Executor}

  @impl Engine
  defdelegate init(conf, opts), to: BasicEngine

  @impl Engine
  def put_meta(_conf, meta, key, value), do: Map.put(meta, key, value)

  @impl Engine
  def check_meta(_conf, meta, _running), do: meta

  @impl Engine
  def refresh(_conf, meta), do: meta

  @impl Engine
  def insert_job(%Config{} = conf, %Changeset{} = changeset) do
    {:ok, execute_job(conf, changeset)}
  end

  @impl Engine
  def insert_job(%Config{} = conf, %Multi{} = multi, name, fun) when is_function(fun, 1) do
    Multi.run(multi, name, fn repo, changes ->
      {:ok, execute_job(%{conf | repo: repo}, fun.(changes))}
    end)
  end

  @impl Engine
  def insert_job(%Config{} = conf, %Multi{} = multi, name, %Changeset{} = changeset) do
    Multi.run(multi, name, fn repo, _changes ->
      {:ok, execute_job(%{conf | repo: repo}, changeset)}
    end)
  end

  @impl Engine
  def insert_all_jobs(%Config{} = conf, changesets) do
    changesets
    |> expand()
    |> Enum.map(&execute_job(conf, &1))
  end

  @impl Engine
  def insert_all_jobs(%Config{} = conf, %Multi{} = multi, name, wrapper) do
    Multi.run(multi, name, fn repo, changes ->
      conf = %{conf | repo: repo}

      jobs =
        wrapper
        |> expand(changes)
        |> Enum.map(&execute_job(conf, &1))

      {:ok, jobs}
    end)
  end

  @impl Engine
  def fetch_jobs(_conf, meta, _running), do: {:ok, {meta, []}}

  @impl Engine
  def complete_job(_conf, _job), do: :ok

  @impl Engine
  def discard_job(_conf, _job), do: :ok

  @impl Engine
  def error_job(_conf, _job, seconds) when is_integer(seconds), do: :ok

  @impl Engine
  def snooze_job(_conf, _job, seconds) when is_integer(seconds), do: :ok

  @impl Engine
  def cancel_job(_conf, _job), do: :ok

  @impl Engine
  def cancel_all_jobs(_conf, _queryable), do: {:ok, {0, []}}

  @impl Engine
  def retry_job(_conf, _job), do: :ok

  @impl Engine
  def retry_all_jobs(_conf, _queryable), do: {:ok, 0}

  # Changeset Helpers

  defp expand(value), do: expand(value, %{})
  defp expand(fun, changes) when is_function(fun, 1), do: expand(fun.(changes), changes)
  defp expand(%{changesets: changesets}, _), do: expand(changesets, %{})
  defp expand(changesets, _) when is_list(changesets), do: changesets

  # Execution Helpers

  defp execute_job(conf, changeset) do
    changeset =
      changeset
      |> Changeset.put_change(:attempted_by, [conf.node])
      |> Changeset.put_change(:attempted_at, utc_now())
      |> Changeset.put_change(:scheduled_at, utc_now())
      |> Changeset.update_change(:args, &json_encode_decode/1)
      |> Changeset.update_change(:meta, &json_encode_decode/1)

    case Changeset.apply_action(changeset, :insert) do
      {:ok, job} ->
        conf
        |> Executor.new(job, safe: false)
        |> Executor.call()
        |> complete_job()

      {:error, changeset} ->
        raise Ecto.InvalidChangesetError, action: :insert, changeset: changeset
    end
  end

  defp json_encode_decode(map) do
    map
    |> Jason.encode!()
    |> Jason.decode!()
  end

  defp complete_job(%{job: job, state: :failure}) do
    error = %{attempt: job.attempt, at: utc_now(), error: format_blamed(job.unsaved_error)}

    %Job{job | errors: [error], state: "retryable", scheduled_at: utc_now()}
  end

  defp complete_job(%{job: job, state: :success}) do
    %Job{job | state: "completed", completed_at: utc_now()}
  end

  defp complete_job(%{job: job, result: {:snooze, snooze}, state: :snoozed}) do
    %Job{job | state: "scheduled", scheduled_at: seconds_from_now(snooze)}
  end

  defp seconds_from_now(seconds), do: DateTime.add(utc_now(), seconds, :second)

  defp format_blamed(%{kind: kind, reason: error, stacktrace: stacktrace}) do
    {blamed, stacktrace} = Exception.blame(kind, error, stacktrace)

    Exception.format(kind, blamed, stacktrace)
  end
end
