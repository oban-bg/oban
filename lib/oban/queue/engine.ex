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
  Format engine meta in a digestible format for queue inspection.
  """
  @callback check_meta(conf(), meta(), running()) :: map()

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
  Mark an `executing`, `available`, `scheduled` or `retryable` job and mark it as `cancelled` to
  prevent it from running again. If the job is currently `executing` it will be killed and
  otherwise it is ignored.
  """
  @callback cancel_job(conf(), Job.t()) :: :ok

  @doc false
  def init(%Config{} = conf, [_ | _] = opts) do
    with_span(:init, conf, fn ->
      conf.engine.init(conf, opts)
    end)
  end

  @doc false
  def refresh(%Config{} = conf, %{} = meta) do
    with_span(:refresh, conf, fn ->
      conf.engine.refresh(conf, meta)
    end)
  end

  @doc false
  def put_meta(%Config{} = conf, %{} = meta, key, value) when is_atom(key) do
    with_span(:put_meta, conf, fn ->
      conf.engine.put_meta(conf, meta, key, value)
    end)
  end

  @doc false
  def check_meta(%Config{} = conf, %{} = meta, %{} = running) do
    conf.engine.check_meta(conf, meta, running)
  end

  @doc false
  def fetch_jobs(%Config{} = conf, %{} = meta, %{} = running) do
    with_span(:fetch_jobs, conf, fn ->
      conf.engine.fetch_jobs(conf, meta, running)
    end)
  end

  @doc false
  def complete_job(%Config{} = conf, %Job{} = job) do
    with_span(:complete_job, conf, %{job: job}, fn ->
      conf.engine.complete_job(conf, job)
    end)
  end

  @doc false
  def discard_job(%Config{} = conf, %Job{} = job) do
    with_span(:discard_job, conf, %{job: job}, fn ->
      conf.engine.discard_job(conf, job)
    end)
  end

  @doc false
  def error_job(%Config{} = conf, %Job{} = job, seconds) when is_integer(seconds) do
    with_span(:error_job, conf, %{job: job}, fn ->
      conf.engine.error_job(conf, job, seconds)
    end)
  end

  @doc false
  def snooze_job(%Config{} = conf, %Job{} = job, seconds) when is_integer(seconds) do
    with_span(:snooze_job, conf, %{job: job}, fn ->
      conf.engine.snooze_job(conf, job, seconds)
    end)
  end

  @doc false
  def cancel_job(%Config{} = conf, %Job{} = job) do
    with_span(:cancel_job, conf, %{job: job}, fn ->
      conf.engine.cancel_job(conf, job)
    end)
  end

  defp with_span(event, %Config{} = conf, additional_meta \\ %{}, fun) do
    tele_meta =
      additional_meta
      |> Map.put(:conf, conf)
      |> Map.put(:engine, conf.engine)

    :telemetry.span([:oban, :engine, event], tele_meta, fn ->
      {fun.(), tele_meta}
    end)
  end
end
