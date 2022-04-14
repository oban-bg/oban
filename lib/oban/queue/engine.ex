defmodule Oban.Queue.Engine do
  @moduledoc false

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
  Refresh a queue to indicate that it is still alive.
  """
  @callback refresh(conf(), meta()) :: meta()

  @doc """
  Store the given key/value pair in the engine meta.
  """
  @callback put_meta(conf(), meta(), atom(), term()) :: meta()

  @doc """
  Format engine meta in a digestible format for queue inspection.
  """
  @callback check_meta(conf(), meta(), running()) :: map()

  @doc """
  Insert a job into the database.
  """
  @callback insert_job(conf(), Job.changeset()) :: {:ok, Job.t()} | {:error, term()}

  @doc """
  Insert a job within an `Ecto.Multi`.
  """
  @callback insert_job(conf(), Multi.t(), Multi.name(), Oban.changeset_or_fun()) :: Multi.t()

  @doc """
  Insert multiple jobs into the database.
  """
  @callback insert_all_jobs(conf(), Oban.changesets_or_wrapper()) :: [Job.t()]

  @doc """
  Insert multiple jobs within an `Ecto.Multi`
  """
  @callback insert_all_jobs(conf(), Multi.t(), Multi.name(), Oban.changesets_or_wrapper_or_fun()) ::
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
  Mark many `executing`, `available`, `scheduled` or `retryable` job as `cancelled` to prevent them
  from running.
  """
  @callback cancel_all_jobs(conf(), queryable()) :: {:ok, {non_neg_integer(), [Job.t()]}}

  @doc """
  Mark a job as `available`, adding attempts if already maxed out. If the job is currently
  `available`, `executing` or `scheduled` it should be ignored.
  """
  @callback retry_job(conf(), Job.t()) :: :ok

  @doc """
  Mark many jobs as `available`, adding attempts if already maxed out. Any jobs currently
  `available`, `executing` or `scheduled` should be ignored.
  """
  @callback retry_all_jobs(conf(), queryable()) :: {:ok, non_neg_integer()}

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
  def insert_job(%Config{} = conf, %Changeset{} = changeset) do
    with_span(:insert_job, conf, %{changeset: changeset}, fn engine ->
      engine.insert_job(conf, changeset)
    end)
  end

  @doc false
  def insert_job(%Config{} = conf, %Multi{} = multi, name, changeset) do
    with_span(:insert_job, conf, %{changeset: changeset}, fn engine ->
      engine.insert_job(conf, multi, name, changeset)
    end)
  end

  @doc false
  def insert_all_jobs(%Config{} = conf, changesets) do
    with_span(:insert_all_jobs, conf, %{changesets: changesets}, fn engine ->
      engine.insert_all_jobs(conf, changesets)
    end)
  end

  @doc false
  def insert_all_jobs(%Config{} = conf, %Multi{} = multi, name, changesets) do
    with_span(:insert_all_jobs, conf, %{changesets: changesets}, fn engine ->
      engine.insert_all_jobs(conf, multi, name, changesets)
    end)
  end

  @doc false
  def fetch_jobs(%Config{} = conf, %{} = meta, %{} = running) do
    with_span(:fetch_jobs, conf, fn engine ->
      engine.fetch_jobs(conf, meta, running)
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
      engine.cancel_all_jobs(conf, queryable)
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
      engine.retry_all_jobs(conf, queryable)
    end)
  end

  defp with_span(event, %Config{} = conf, tele_meta \\ %{}, fun) do
    tele_meta = Map.merge(tele_meta, %{conf: conf, engine: conf.engine})

    :telemetry.span([:oban, :engine, event], tele_meta, fn ->
      engine = Process.get(:oban_engine, conf.engine)

      {fun.(engine), tele_meta}
    end)
  end
end
