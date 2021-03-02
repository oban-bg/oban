defmodule Oban.Queue.Engine do
  @moduledoc false

  alias Oban.{Config, Job}

  @type conf :: Config.t()
  @type meta :: map()
  @type opts :: Keyword.t()
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
  Fetch available jobs for the given queue, up to configured limits.
  """
  @callback fetch_jobs(conf(), meta(), running()) :: {:ok, [Job.t()]} | {:error, term()}

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
  def fetch_jobs(%Config{} = conf, %{} = meta, %{} = running) do
    conf.engine.fetch_jobs(conf, meta, running)
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
