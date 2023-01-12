defmodule Oban.Engines.Inline do
  @moduledoc """
  A testing-specific engine that's used when Oban's started with `testing: :inline`.

  ## Usage

  This is meant for testing and shouldn't be configured directly:

      Oban.start_link(repo: MyApp.Repo, testing: :inline)
  """

  @behaviour Oban.Engine

  import DateTime, only: [utc_now: 0]

  alias Ecto.Changeset
  alias Oban.{Config, Engine, Job}
  alias Oban.Queue.Executor

  @impl Engine
  def init(_conf, opts), do: {:ok, Map.new(opts)}

  @impl Engine
  def put_meta(_conf, meta, key, value), do: Map.put(meta, key, value)

  @impl Engine
  def check_meta(_conf, meta, _running), do: meta

  @impl Engine
  def refresh(_conf, meta), do: meta

  @impl Engine
  def shutdown(_conf, meta), do: meta

  @impl Engine
  def insert_job(%Config{} = conf, %Changeset{} = changeset, _opts) do
    {:ok, execute_job(conf, changeset)}
  end

  @impl Engine
  def insert_all_jobs(%Config{} = conf, changesets, _opts) do
    changesets
    |> expand()
    |> Enum.map(&execute_job(conf, &1))
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
  def cancel_all_jobs(_conf, _queryable), do: {:ok, []}

  @impl Engine
  def retry_job(_conf, _job), do: :ok

  @impl Engine
  def retry_all_jobs(_conf, _queryable), do: {:ok, []}

  # Changeset Helpers

  defp expand(value), do: expand(value, %{})
  defp expand(fun, changes) when is_function(fun, 1), do: expand(fun.(changes), changes)
  defp expand(%{changesets: changesets}, _), do: expand(changesets, %{})
  defp expand(changesets, _) when is_list(changesets), do: changesets

  # Execution Helpers

  defp execute_job(conf, changeset) do
    changeset =
      changeset
      |> Changeset.put_change(:attempt, 1)
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
    %Job{job | errors: [Job.format_attempt(job)], state: "retryable", scheduled_at: utc_now()}
  end

  defp complete_job(%{job: job, state: :cancelled}) do
    %Job{job | errors: [Job.format_attempt(job)], state: "cancelled", cancelled_at: utc_now()}
  end

  defp complete_job(%{job: job, state: state}) when state in [:discard, :exhausted] do
    %Job{job | errors: [Job.format_attempt(job)], state: "discarded", discarded_at: utc_now()}
  end

  defp complete_job(%{job: job, state: :success}) do
    %Job{job | state: "completed", completed_at: utc_now()}
  end

  defp complete_job(%{job: job, result: {:snooze, snooze}, state: :snoozed}) do
    %Job{job | state: "scheduled", scheduled_at: DateTime.add(utc_now(), snooze, :second)}
  end
end
