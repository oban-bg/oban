defmodule Oban.Engine do
  @moduledoc """
  Defines an Engine for job orchestration.

  Engines are responsible for all non-plugin database interaction, from inserting through
  executing jobs.

  Oban ships with three Engine implementations:

  1. `Basic` — The default engine for development, production, and manual testing mode.
  2. `Inline` — Designed specifically for testing, it executes jobs immediately, in-memory, as
     they are inserted.
  3. `Lite` - The engine for running Oban using SQLite3.

  > #### 🌟 SmartEngine {: .info}
  >
  > The Basic engine lacks advanced functionality such as global limits, rate limits, and
  > unique bulk insert. For those features and more, see the [`SmartEngine` in Oban
  > Pro](https://getoban.pro/docs/pro/smart_engine.html).
  """

  alias Ecto.{Changeset, Multi}
  alias Oban.{Config, Job}

  @type conf :: Config.t()
  @type job :: Job.t()
  @type meta :: map()
  @type opts :: Keyword.t()
  @type queryable :: Ecto.Queryable.t()
  @type running :: map()
  @type seconds :: pos_integer()

  @doc """
  Initialize metadata for a queue engine.

  Queue metadata is used to identify and track subsequent actions such as fetching or staging
  jobs.
  """
  @callback init(conf(), opts()) :: {:ok, meta()} | {:error, term()}

  @doc """
  Store the given key/value pair in the engine meta.
  """
  @callback put_meta(conf(), meta(), atom(), term()) :: meta()

  @doc """
  Format engine meta in a digestible format for queue inspection.
  """
  @callback check_meta(conf(), meta(), running()) :: map()

  @doc """
  Refresh a queue to indicate that it is still alive.
  """
  @callback refresh(conf(), meta()) :: meta()

  @doc """
  Prepare a queue engine for shutdown.

  The queue process is expected to stop processing new jobs after shutdown starts, though it may
  continue executing jobs that are already running.
  """
  @callback shutdown(conf(), meta()) :: meta()

  @doc """
  Insert a job into the database.
  """
  @callback insert_job(conf(), Job.changeset(), opts()) :: {:ok, Job.t()} | {:error, term()}

  @doc deprecated: "Handled automatically by engine dispatch."
  @callback insert_job(conf(), Multi.t(), Multi.name(), [Job.changeset()], opts()) :: Multi.t()

  @doc """
  Insert multiple jobs into the database.
  """
  @callback insert_all_jobs(conf(), [Job.changeset()], opts()) :: [Job.t()]

  @doc deprecated: "Handled automatically by engine dispatch."
  @callback insert_all_jobs(conf(), Multi.t(), Multi.name(), [Job.changeset()], opts()) ::
              Multi.t()

  @doc """
  Fetch available jobs for the given queue, up to configured limits.
  """
  @callback fetch_jobs(conf(), meta(), running()) :: {:ok, {meta(), [Job.t()]}} | {:error, term()}

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

  @doc """
  Mark an `executing`, `available`, `scheduled` or `retryable` job as `cancelled` to prevent it
  from running.
  """
  @callback cancel_job(conf(), Job.t()) :: :ok

  @doc """
  Mark a job as `available`, adding attempts if already maxed out. If the job is currently
  `available`, `executing` or `scheduled` it should be ignored.
  """
  @callback retry_job(conf(), Job.t()) :: :ok

  @doc """
  Mark many `executing`, `available`, `scheduled` or `retryable` job as `cancelled` to prevent them
  from running.
  """
  @callback cancel_all_jobs(conf(), queryable()) :: {:ok, [Job.t()]}

  @doc """
  Mark many jobs as `available`, adding attempts if already maxed out. Any jobs currently
  `available`, `executing` or `scheduled` should be ignored.
  """
  @callback retry_all_jobs(conf(), queryable()) :: {:ok, [Job.t()]}

  @optional_callbacks [insert_all_jobs: 5, insert_job: 5]

  @doc false
  def init(%Config{} = conf, [_ | _] = opts) do
    with_span(:init, conf, fn engine ->
      engine.init(conf, opts)
    end)
  end

  @doc false
  def refresh(%Config{} = conf, %{} = meta) do
    with_span(:refresh, conf, fn engine ->
      engine.refresh(conf, meta)
    end)
  end

  @doc false
  def shutdown(%Config{} = conf, %{} = meta) do
    with_span(:shutdown, conf, fn engine ->
      engine.shutdown(conf, meta)
    end)
  end

  @doc false
  def put_meta(%Config{} = conf, %{} = meta, key, value) when is_atom(key) do
    with_span(:put_meta, conf, fn engine ->
      engine.put_meta(conf, meta, key, value)
    end)
  end

  @doc false
  def check_meta(%Config{} = conf, %{} = meta, %{} = running) do
    with_span(:check_meta, conf, fn engine ->
      engine.check_meta(conf, meta, running)
    end)
  end

  @doc false
  def insert_job(%Config{} = conf, %Changeset{} = changeset, opts) do
    with_span(:insert_job, conf, %{opts: opts}, fn engine ->
      with {:ok, job} <- engine.insert_job(conf, changeset, opts) do
        {:meta, {:ok, job}, %{job: job}}
      end
    end)
  end

  @doc false
  def insert_job(%Config{} = conf, %Multi{} = multi, name, fun, opts) when is_function(fun, 1) do
    Multi.run(multi, name, fn repo, changes ->
      insert_job(%{conf | repo: repo}, fun.(changes), opts)
    end)
  end

  def insert_job(%Config{} = conf, %Multi{} = multi, name, changeset, opts) do
    Multi.run(multi, name, fn repo, _changes ->
      insert_job(%{conf | repo: repo}, changeset, opts)
    end)
  end

  @doc false
  def insert_all_jobs(%Config{} = conf, changesets, opts) do
    with_span(:insert_all_jobs, conf, %{opts: opts}, fn engine ->
      jobs = engine.insert_all_jobs(conf, expand(changesets, %{}), opts)

      {:meta, jobs, %{jobs: jobs}}
    end)
  end

  @doc false
  def insert_all_jobs(%Config{} = conf, %Multi{} = multi, name, wrapper, opts) do
    Multi.run(multi, name, fn repo, changes ->
      {:ok, insert_all_jobs(%{conf | repo: repo}, expand(wrapper, changes), opts)}
    end)
  end

  @doc false
  def fetch_jobs(%Config{} = conf, %{} = meta, %{} = running) do
    with_span(:fetch_jobs, conf, fn engine ->
      {:ok, {meta, jobs}} = engine.fetch_jobs(conf, meta, running)
      {:meta, {:ok, {meta, jobs}}, %{jobs: jobs}}
    end)
  end

  @doc false
  def complete_job(%Config{} = conf, %Job{} = job) do
    with_span(:complete_job, conf, %{job: job}, fn engine ->
      engine.complete_job(conf, job)
    end)
  end

  @doc false
  def discard_job(%Config{} = conf, %Job{} = job) do
    with_span(:discard_job, conf, %{job: job}, fn engine ->
      engine.discard_job(conf, job)
    end)
  end

  @doc false
  def error_job(%Config{} = conf, %Job{} = job, seconds) when is_integer(seconds) do
    with_span(:error_job, conf, %{job: job}, fn engine ->
      engine.error_job(conf, job, seconds)
    end)
  end

  @doc false
  def snooze_job(%Config{} = conf, %Job{} = job, seconds) when is_integer(seconds) do
    with_span(:snooze_job, conf, %{job: job}, fn engine ->
      engine.snooze_job(conf, job, seconds)
    end)
  end

  @doc false
  def cancel_job(%Config{} = conf, %Job{} = job) do
    with_span(:cancel_job, conf, %{job: job}, fn engine ->
      engine.cancel_job(conf, job)
    end)
  end

  @doc false
  def cancel_all_jobs(%Config{} = conf, queryable) do
    with_span(:cancel_all_jobs, conf, fn engine ->
      with {:ok, jobs} <- engine.cancel_all_jobs(conf, queryable) do
        {:meta, {:ok, jobs}, %{jobs: jobs}}
      end
    end)
  end

  @doc false
  def retry_job(%Config{} = conf, %Job{} = job) do
    with_span(:retry_job, conf, %{job: job}, fn engine ->
      engine.retry_job(conf, job)
    end)
  end

  @doc false
  def retry_all_jobs(%Config{} = conf, queryable) do
    with_span(:retry_all_jobs, conf, fn engine ->
      with {:ok, jobs} <- engine.retry_all_jobs(conf, queryable) do
        {:meta, {:ok, jobs}, %{jobs: jobs}}
      end
    end)
  end

  defp expand(fun, changes) when is_function(fun, 1), do: expand(fun.(changes), changes)
  defp expand(%{changesets: changesets}, _), do: expand(changesets, %{})
  defp expand(changesets, _) when is_list(changesets), do: changesets

  defp with_span(event, %Config{} = conf, base_meta \\ %{}, fun) do
    base_meta = Map.merge(base_meta, %{conf: conf, engine: conf.engine})

    :telemetry.span([:oban, :engine, event], base_meta, fn ->
      engine = Config.get_engine(conf)

      case fun.(engine) do
        {:meta, result, more_meta} ->
          {result, Map.merge(base_meta, more_meta)}

        result ->
          {result, base_meta}
      end
    end)
  end
end
