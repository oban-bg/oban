defmodule Oban.Queue.Engine do
  @moduledoc false

  alias Oban.{Config, Job}

  @type conf :: Config.t()
  @type opts :: Keyword.t()
  @type seconds :: pos_integer()

  @type meta :: %{
          :paused => boolean(),
          :queue => binary(),
          :limit => pos_integer(),
          :running => map(),
          :started_at => DateTime.t(),
          :updated_at => DateTime.t(),
          optional(atom()) => term()
        }

  @doc """
  Initialize metadata for a queue engine.

  Queue metadata is used to identify and track subsequent actions such as fetching or staging
  jobs.
  """
  @callback init(conf(), opts()) :: {:ok, meta()} | {:error, term()}

  @doc """
  Refresh a queue to indicate that it is still alive.
  """
  @callback refresh(conf(), meta()) :: meta()

  @doc """
  Store the given key/value pair in the engine meta.
  """
  @callback put_meta(conf(), meta(), atom(), term()) :: meta()

  @doc """
  Record that a job started.
  """
  @callback update_meta(conf(), meta(), atom(), (term() -> term())) :: meta()

  @doc """
  Fetch available jobs for the given queue, up to configured limits.
  """
  @callback fetch_jobs(conf(), meta()) :: {:ok, [Job.t()]} | {:error, term()}

  @doc """
  Record that a job completed successfully.
  """
  @callback complete_job(conf(), Job.t()) :: :ok

  @doc """
  Transition a job to `discarded` and record an optional reason that it shouldn't be ran again.
  """
  @callback discard_job(conf(), Job.t()) :: :ok

  @doc """
  Record an executing job's errors and either retry or discard it, depending on whether it has
  exhausted its available attempts.
  """
  @callback error_job(conf(), Job.t(), seconds()) :: :ok

  @doc """
  Reschedule an executing job to run some number of seconds in the future.
  """
  @callback snooze_job(conf(), Job.t(), seconds()) :: :ok

  @doc false
  def init(%Config{} = conf, [_ | _] = opts) do
    conf.engine.init(conf, opts)
  end

  @doc false
  def refresh(%Config{} = conf, %{} = meta) do
    conf.engine.refresh(conf, meta)
  end

  @doc false
  def put_meta(%Config{} = conf, %{} = meta, key, value) when is_atom(key) do
    conf.engine.put_meta(conf, meta, key, value)
  end

  @doc false
  def update_meta(%Config{} = conf, %{} = meta, key, fun) when is_function(fun, 1) do
    conf.engine.update_meta(conf, meta, key, fun)
  end

  @doc false
  def fetch_jobs(%Config{} = conf, %{} = meta) do
    conf.engine.fetch_jobs(conf, meta)
  end

  @doc false
  def complete_job(%Config{} = conf, %Job{} = job) do
    conf.engine.complete_job(conf, job)
  end

  @doc false
  def discard_job(%Config{} = conf, %Job{} = job) do
    conf.engine.discard_job(conf, job)
  end

  @doc false
  def error_job(%Config{} = conf, %Job{} = job, seconds) when is_integer(seconds) do
    conf.engine.error_job(conf, job, seconds)
  end

  @doc false
  def snooze_job(%Config{} = conf, %Job{} = job, seconds) when is_integer(seconds) do
    conf.engine.snooze_job(conf, job, seconds)
  end
end

defmodule Oban.Queue.BasicEngine do
  @moduledoc false

  @behaviour Oban.Queue.Engine

  import Ecto.Query
  import DateTime, only: [utc_now: 0]

  alias Oban.{Config, Job, Repo}

  @impl true
  def init(%Config{} = conf, opts) do
    meta =
      opts
      |> Keyword.put_new(:paused, false)
      |> Keyword.put(:running, %{})
      |> Keyword.put(:node, conf.node)
      |> Keyword.put(:started_at, utc_now())
      |> Keyword.put(:updated_at, utc_now())
      |> Map.new()

    {:ok, meta}
  end

  @impl true
  def put_meta(_conf, %{} = meta, key, value) do
    Map.put(meta, key, value)
  end

  @impl true
  def update_meta(_conf, %{} = meta, key, fun) do
    Map.update!(meta, key, fun)
  end

  @impl true
  def refresh(_conf, %{} = meta) do
    %{meta | updated_at: utc_now()}
  end

  @impl true
  def fetch_jobs(_conf, %{paused: true}), do: {:ok, []}

  def fetch_jobs(_conf, %{limit: limit, running: %{map: map}}) when map_size(map) >= limit do
    {:ok, []}
  end

  def fetch_jobs(%Config{} = conf, %{} = meta) do
    demand = meta.limit - map_size(meta.running)

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
          {0, nil} -> []
          {_count, jobs} -> jobs
        end
      end
    )
  end

  @impl true
  def complete_job(%Config{} = conf, %Job{} = job) do
    Repo.update_all(
      conf,
      where(Job, id: ^job.id),
      set: [state: "completed", completed_at: utc_now()]
    )

    :ok
  end

  @impl true
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

  @impl true
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

  @impl true
  def snooze_job(%Config{} = conf, %Job{id: id}, seconds) when is_integer(seconds) do
    scheduled_at = DateTime.add(utc_now(), seconds)

    updates = [
      set: [state: "scheduled", scheduled_at: scheduled_at],
      inc: [max_attempts: 1]
    ]

    Repo.update_all(conf, where(Job, id: ^id), updates)

    :ok
  end

  # Helpers

  defp seconds_from_now(seconds), do: DateTime.add(utc_now(), seconds, :second)

  defp format_blamed(%{kind: kind, reason: error, stacktrace: stacktrace}) do
    {blamed, stacktrace} = Exception.blame(kind, error, stacktrace)

    Exception.format(kind, blamed, stacktrace)
  end
end
