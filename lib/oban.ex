defmodule Oban do
  @external_resource readme = Path.join([__DIR__, "../README.md"])

  @moduledoc readme
             |> File.read!()
             |> String.split("<!-- MDOC -->")
             |> Enum.fetch!(1)

  @moduledoc since: "0.1.0"

  use Supervisor

  import Oban.Notifier, only: [signal: 0]

  alias Ecto.{Changeset, Multi}
  alias Oban.{Config, Job, Midwife, Notifier, Pruner, Query}
  alias Oban.Crontab.Scheduler
  alias Oban.Queue.Producer
  alias Oban.Queue.Supervisor, as: QueueSupervisor

  @type option ::
          {:beats_maxage, pos_integer()}
          | {:circuit_backoff, timeout()}
          | {:crontab, [Config.cronjob()]}
          | {:dispatch_cooldown, pos_integer()}
          | {:name, module()}
          | {:node, binary()}
          | {:poll_interval, pos_integer()}
          | {:prefix, binary()}
          | {:prune, :disabled | {:maxlen, pos_integer()} | {:maxage, pos_integer()}}
          | {:prune_interval, pos_integer()}
          | {:prune_limit, pos_integer()}
          | {:queues, [{atom(), pos_integer()}]}
          | {:repo, module()}
          | {:rescue_after, pos_integer()}
          | {:rescue_interval, pos_integer()}
          | {:shutdown_grace_period, timeout()}
          | {:timezone, Calendar.time_zone()}
          | {:verbose, false | Logger.level()}

  @type queue_name :: atom() | binary()

  defguardp is_queue(name)
            when (is_binary(name) and byte_size(name) > 0) or (is_atom(name) and not is_nil(name))

  defguardp is_limit(limit) when is_integer(limit) and limit > 0

  @doc """
  Starts an `Oban` supervision tree linked to the current process.

  ## Options

  These options are required; without them the supervisor won't start

  * `:name` — used for supervisor registration, defaults to `Oban`
  * `:repo` — specifies the Ecto repo used to insert and retrieve jobs.

  ### Primary Options

  These options determine what the system does at a high level, i.e. which queues to run or how
  vigorously to prune.

  * `:crontab` — a list of cron expressions that enqueue jobs on a periodic basis. See "Periodic
    (CRON) Jobs" in the module docs.

    For testing purposes `:crontab` may be set to `false` or `nil`, which disables scheduling.
  * `:node` — used to identify the node that the supervision tree is running in. If no value is
    provided it will use the `node` name in a distributed system, or the `hostname` in an isolated
    node. See "Node Name" below.
  * `:prefix` — the query prefix, or schema, to use for inserting and executing jobs. An
    `oban_jobs` table must exist within the prefix. See the "Prefix Support" section in the module
    documentation for more details.
  * `:prune` - configures job pruning behavior, see "Pruning Historic Jobs" for more information.
    Defaults to `{:maxlen, 1_000}`, meaning the jobs table will retain roughly 1,000 completed
    jobs.
  * `:queues` — a keyword list where the keys are queue names and the values are the concurrency
    setting. For example, setting queues to `[default: 10, exports: 5]` would start the queues
    `default` and `exports` with a combined concurrency level of 20. The concurrency setting
    specifies how many jobs _each queue_ will run concurrently.

    For testing purposes `:queues` may be set to `false` or `nil`, which effectively disables all
    job dispatching.
  * `:timezone` — which timezone to use when scheduling cron jobs. To use a timezone other than
    the default of "Etc/UTC" you *must* have a timezone database like [tzdata][tzdata] installed
    and configured.
  * `:verbose` — either `false` to disable logging or a standard log level (`:error`, `:warn`,
    `:info`, `:debug`). This determines whether queries are logged or not; overriding the repo's
    configured log level. Defaults to `false`, where no queries are logged.

  [tzdata]: https://hexdocs.pm/tzdata

  ### Twiddly Options

  Additional options used to tune system behaviour. These are primarily useful for testing or
  troubleshooting and don't usually need modification.

  * `:beats_maxage` — the number of seconds that heartbeat rows in the `oban_beats` table should
    be retained. The value must be greater than `60` (the value of `rescue_after`). Defaults to
    `300s`, or five minutes.
  * `:circuit_backoff` — the number of milliseconds until queries are attempted after a database
    error. All processes communicating with the database are equipped with circuit breakers and
    will use this for the backoff. Defaults to `30_000ms`.
  * `:dispatch_cooldown` — the minimum number of milliseconds a producer will wait before fetching
    and running more jobs. A slight cooldown period prevents a producer from flooding with
    messages and thrashing the database. The cooldown period _directly impacts_ a producer's
    throughput: jobs per second for a single queue is calculated by `(1000 / cooldown) * limit`.
    For example, with a `5ms` cooldown and a queue limit of `25` a single queue can run 2,500
    jobs/sec.

    The default is `5ms` and the minimum is `1ms`, which is likely faster than the database can
    return new jobs to run.
  * `:poll_interval` - the number of milliseconds between polling for new jobs in a queue. This
    is directly tied to the resolution of _scheduled_ jobs. For example, with a `poll_interval` of
    `5_000ms`, scheduled jobs are checked every 5 seconds. The default is `1_000ms`.
  * `:prune_interval` — the number of milliseconds between calls to prune historic jobs. The
    default is `60_000ms`, or one minute.
  * `:prune_limit` – the maximum number of jobs that can be pruned at each prune interval. The
    default is `5_000`.
  * `:rescue_after` — the number of seconds after an executing job without any pulse activity may
    be rescued. This value _must_ be greater than the `poll_interval`. The default is `60s`.
  * `:rescue_interval` — the number of milliseconds between calls to rescue orphaned jobs, the
    default is `60_000ms`, or one minute.
  * `:shutdown_grace_period` - the amount of time a queue will wait for executing jobs to complete
    before hard shutdown, specified in milliseconds. The default is `15_000`, or 15 seconds.

  ## Examples

  To start an `Oban` supervisor within an application's supervision tree:

      def start(_type, _args) do
        children = [MyApp.Repo, {Oban, queues: [default: 50]}]

        Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)
      end

  ## Node Name

  When the `node` value hasn't been configured it is generated based on the environment:

  * In a distributed system the node name is used
  * In a Heroku environment the system environment's `DYNO` value is used
  * Otherwise, the system hostname is used
  """
  @doc since: "0.1.0"
  @spec start_link([option()]) :: Supervisor.on_start()
  def start_link(opts) when is_list(opts) do
    conf = Config.new(opts)

    Supervisor.start_link(__MODULE__, conf, name: conf.name)
  end

  @impl Supervisor
  def init(%Config{name: name, queues: queues} = conf) do
    children = [
      {Config, conf: conf, name: child_name(name, "Config")},
      {Pruner, conf: conf, name: child_name(name, "Pruner")},
      {Notifier, conf: conf, name: child_name(name, "Notifier")},
      {Midwife, conf: conf, name: child_name(name, "Midwife")},
      {Scheduler, conf: conf, name: child_name(name, "Scheduler")}
    ]

    children = children ++ Enum.map(queues, &QueueSupervisor.child_spec(&1, conf))

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Retrieve the config struct for a named Oban supervision tree.
  """
  @doc since: "0.2.0"
  @spec config(name :: atom()) :: Config.t()
  def config(name \\ __MODULE__) when is_atom(name) do
    name
    |> child_name("Config")
    |> Config.get()
  end

  @doc """
  Insert a new job into the database for execution.

  This and the other `insert` variants are the recommended way to enqueue jobs because they
  support features like unique jobs.

  See the section on "Unique Jobs" for more details.

  ## Example

  Insert a single job:

      {:ok, job} = Oban.insert(MyApp.Worker.new(%{id: 1}))

  Insert a job while ensuring that it is unique within the past 30 seconds:

      {:ok, job} = Oban.insert(MyApp.Worker.new(%{id: 1}, unique: [period: 30]))
  """
  @doc since: "0.7.0"
  @spec insert(name :: atom(), changeset :: Changeset.t(Job.t())) ::
          {:ok, Job.t()} | {:error, Changeset.t()}
  def insert(name \\ __MODULE__, %Changeset{} = changeset) when is_atom(name) do
    name
    |> config()
    |> Query.fetch_or_insert_job(changeset)
  end

  @doc """
  Put a job insert operation into an `Ecto.Multi`.

  Like `insert/2`, this variant is recommended over `Ecto.Multi.insert` beause it supports all of
  Oban's features, i.e. unique jobs.

  See the section on "Unique Jobs" for more details.

  ## Example

      Ecto.Multi.new()
      |> Oban.insert("job-1", MyApp.Worker.new(%{id: 1}))
      |> Oban.insert("job-2", MyApp.Worker.new(%{id: 2}))
      |> MyApp.Repo.transaction()
  """
  @doc since: "0.7.0"
  @spec insert(
          name :: atom(),
          multi :: Multi.t(),
          multi_name :: Multi.name(),
          changeset :: Changeset.t(Job.t())
        ) :: Multi.t()
  def insert(name \\ __MODULE__, %Multi{} = multi, multi_name, %Changeset{} = changeset)
      when is_atom(name) do
    name
    |> config()
    |> Query.fetch_or_insert_job(multi, multi_name, changeset)
  end

  @doc """
  Similar to `insert/2`, but raises an `Ecto.InvalidChangesetError` if the job can't be inserted.

  ## Example

      job = Oban.insert!(MyApp.Worker.new(%{id: 1}))
  """
  @doc since: "0.7.0"
  @spec insert!(name :: atom(), changeset :: Changeset.t(Job.t())) :: Job.t()
  def insert!(name \\ __MODULE__, %Changeset{} = changeset) when is_atom(name) do
    case insert(name, changeset) do
      {:ok, job} ->
        job

      {:error, changeset} ->
        raise Ecto.InvalidChangesetError, action: :insert, changeset: changeset
    end
  end

  @doc """
  Insert multiple jobs into the database for execution.

  Insertion respects `prefix` and `verbose` settings, but it *does not use* per-job unique
  configuration. You must use `insert/2,4` or `insert!/2` for per-job unique support.

  There are a few important differences between this function and `Ecto.Repo.insert_all/3`:

  1. This function always returns a list rather than a tuple of `{count, records}`
  2. This function requires a list of changesets rather than a list of maps or keyword lists

  ## Example

      1..100
      |> Enum.map(&MyApp.Worker.new(%{id: &1}))
      |> Oban.insert_all()
  """
  @doc since: "0.9.0"
  @spec insert_all(name :: atom(), jobs :: [Changeset.t(Job.t())]) :: [Job.t()]
  def insert_all(name \\ __MODULE__, changesets) when is_atom(name) and is_list(changesets) do
    name
    |> config()
    |> Query.insert_all_jobs(changesets)
  end

  @doc """
  Put an `insert_all` operation into an `Ecto.Multi`.

  This function supports the same features and has the same caveats as `insert_all/2`.

  ## Example

      changesets = Enum.map(0..100, MyApp.Worker.new(%{id: &1}))

      Ecto.Multi.new()
      |> Oban.insert_all(:jobs, changesets)
      |> MyApp.Repo.transaction()
  """
  @doc since: "0.9.0"
  @spec insert_all(
          name :: atom(),
          multi :: Multi.t(),
          multi_name :: Multi.name(),
          changeset :: [Changeset.t(Job.t())]
        ) :: Multi.t()
  def insert_all(name \\ __MODULE__, %Multi{} = multi, multi_name, changesets)
      when is_list(changesets) do
    name
    |> config()
    |> Query.insert_all_jobs(multi, multi_name, changesets)
  end

  @type drain_option :: {:with_scheduled, boolean()}
  @type drain_result :: %{success: non_neg_integer(), failure: non_neg_integer()}

  @doc """
  Synchronously execute all available jobs in a queue.

  See `drain_queue/3`.
  """
  @doc since: "0.4.0"
  @spec drain_queue(queue :: atom() | binary()) :: drain_result()
  def drain_queue(queue) when is_queue(queue) do
    drain_queue(__MODULE__, queue, [])
  end

  @doc """
  Synchronously execute all available jobs in a queue.

  See `drain_queue/3`.
  """
  @doc since: "0.4.0"
  def drain_queue(queue, opts) when is_queue(queue) and is_list(opts) do
    drain_queue(__MODULE__, queue, opts)
  end

  def drain_queue(name, queue) when is_atom(name) and is_queue(queue) do
    drain_queue(name, queue, [])
  end

  @doc """
  Synchronously execute all available jobs in a queue. All execution happens within the current
  process and it is guaranteed not to raise an error or exit.

  Draining a queue from within the current process is especially useful for testing. Jobs that are
  enqueued by a process when Ecto is in sandbox mode are only visible to that process. Calling
  `drain_queue/3` allows you to control when the jobs are executed and to wait synchronously for
  all jobs to complete.

  ## Example

  Drain a queue with three available jobs, two of which succeed and one of which fails:

      Oban.drain_queue(:default)
      %{success: 2, failure: 1}

  ## Failures & Retries

  Draining a queue uses the same execution mechanism as regular job dispatch. That means that any
  job failures or crashes are captured and result in a retry. Retries are scheduled in the future
  with backoff and won't be retried immediately.

  Exceptions are _not_ raised in to the calling process. If you expect jobs to fail, would like to
  track failures, or need to check for specific errors you can use one of these mechanisms:

  * Check for side effects from job execution
  * Use telemetry events to track success and failure
  * Check the database for jobs with errors

  ## Scheduled Jobs

  By default, `drain_queue/3` will execute all currently available jobs. In order to execute scheduled
  jobs, you may pass the `:with_scheduled` flag which will cause scheduled jobs to be marked as
  `available` beforehand.

      # This will execute all scheduled jobs.
      Oban.drain_queue(:default, with_scheduled: true)
      %{success: 1, failure: 0}
  """
  @doc since: "0.4.0"
  @spec drain_queue(name :: atom(), queue :: queue_name(), [drain_option()]) ::
          drain_result()
  def drain_queue(name, queue, opts) when is_atom(name) and is_queue(queue) and is_list(opts) do
    Producer.drain(to_string(queue), config(name), opts)
  end

  @doc """
  Start a new supervised queue across all connected nodes.

  ## Example

  Start the `:priority` queue with a concurrency limit of 10.

      Oban.start_queue(:priority, 10)
      :ok
  """
  @doc since: "0.12.0"
  @spec start_queue(name :: atom(), queue :: queue_name(), limit :: pos_integer()) :: :ok
  def start_queue(name \\ __MODULE__, queue, limit) when is_queue(queue) and is_limit(limit) do
    name
    |> config()
    |> Query.notify(signal(), %{action: :start, queue: queue, limit: limit})
  end

  @doc """
  Pause a running queue, preventing it from executing any new jobs. All running jobs will remain
  running until they are finished.

  When shutdown begins all queues are paused.

  ## Example

  Pause the default queue:

      Oban.pause_queue(:default)
      :ok
  """
  @doc since: "0.2.0"
  @spec pause_queue(name :: atom(), queue :: queue_name()) :: :ok
  def pause_queue(name \\ __MODULE__, queue) when is_queue(queue) do
    name
    |> config()
    |> Query.notify(signal(), %{action: :pause, queue: queue})
  end

  @doc """
  Resume executing jobs in a paused queue.

  ## Example

  Resume a paused default queue:

      Oban.resume_queue(:default)
      :ok
  """
  @doc since: "0.2.0"
  @spec resume_queue(name :: atom(), queue :: queue_name()) :: :ok
  def resume_queue(name \\ __MODULE__, queue) when is_queue(queue) do
    name
    |> config()
    |> Query.notify(signal(), %{action: :resume, queue: queue})
  end

  @doc """
  Scale the concurrency for a queue.

  ## Example

  Scale a queue up, triggering immediate execution of queued jobs:

      Oban.scale_queue(:default, 50)
      :ok

  Scale the queue back down, allowing executing jobs to finish:

      Oban.scale_queue(:default, 5)
      :ok
  """
  @doc since: "0.2.0"
  @spec scale_queue(name :: atom(), queue :: queue_name(), scale :: pos_integer()) :: :ok
  def scale_queue(name \\ __MODULE__, queue, scale) when is_queue(queue) and is_limit(scale) do
    name
    |> config()
    |> Query.notify(signal(), %{action: :scale, queue: queue, scale: scale})
  end

  @doc """
  Shutdown a queue's supervision tree and stop running jobs for that queue across all running
  nodes.

  The shutdown process pauses the queue first and allows current jobs to exit gracefully,
  provided they finish within the shutdown limit.

  ## Example

      Oban.stop_queue(:default)
      :ok
  """
  @doc since: "0.12.0"
  @spec stop_queue(name :: atom(), queue :: queue_name()) :: :ok
  def stop_queue(name \\ __MODULE__, queue) when is_atom(name) and is_queue(queue) do
    name
    |> config()
    |> Query.notify(signal(), %{action: :stop, queue: queue})
  end

  @doc """
  Kill an actively executing job and mark it as `discarded`, ensuring that it won't be retried.

  If the job happens to fail before it can be killed the state is set to `discarded`. However,
  if it manages to complete successfully then the state will still be `completed`.

  ## Example

  Kill a long running job with an id of `1`:

      Oban.kill_job(1)
      :ok
  """
  @doc since: "0.2.0"
  @spec kill_job(name :: atom(), job_id :: pos_integer()) :: :ok
  def kill_job(name \\ __MODULE__, job_id) when is_integer(job_id) do
    name
    |> config()
    |> Query.notify(signal(), %{action: :pkill, job_id: job_id})
  end

  defp child_name(name, child), do: Module.concat(name, child)
end
