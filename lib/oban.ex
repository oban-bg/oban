defmodule Oban do
  @external_resource readme = Path.join([__DIR__, "../README.md"])

  @moduledoc readme
             |> File.read!()
             |> String.split("<!-- MDOC -->")
             |> Enum.fetch!(1)

  @moduledoc since: "0.1.0"

  use Supervisor

  alias Ecto.{Changeset, Multi}
  alias Oban.{Config, Job, Midwife, Notifier, Query, Registry, Telemetry}
  alias Oban.Queue.{Drainer, Producer}
  alias Oban.Queue.Supervisor, as: QueueSupervisor

  @type name :: term

  @type queue_name :: atom() | binary()

  @type queue_option ::
          {:queue, queue_name()}
          | {:limit, pos_integer()}
          | {:local_only, boolean()}

  @type queue_state :: %{
          limit: pos_integer(),
          node: binary(),
          nonce: binary(),
          paused: boolean(),
          queue: queue_name(),
          running: [pos_integer()],
          started_at: DateTime.t()
        }

  @type option ::
          {:circuit_backoff, timeout()}
          | {:dispatch_cooldown, pos_integer()}
          | {:get_dynamic_repo, nil | (() -> pid() | atom())}
          | {:log, false | Logger.level()}
          | {:name, name()}
          | {:node, binary()}
          | {:plugins, [module() | {module() | Keyword.t()}]}
          | {:prefix, binary()}
          | {:queues, [{queue_name(), pos_integer() | Keyword.t()}]}
          | {:repo, module()}
          | {:shutdown_grace_period, timeout()}

  @type drain_option ::
          {:queue, queue_name()}
          | {:with_safety, boolean()}
          | {:with_scheduled, boolean()}

  @type drain_result :: %{failure: non_neg_integer(), success: non_neg_integer()}

  @type wrapper :: %{:changesets => Job.changeset_list(), optional(atom()) => term()}

  @type changesets_or_wrapper :: Job.changeset_list() | wrapper()

  @doc """
  Starts an `Oban` supervision tree linked to the current process.

  ## Options

  These options are required; without them the supervisor won't start

  * `:name` — used for supervisor registration, defaults to `Oban`
  * `:repo` — specifies the Ecto repo used to insert and retrieve jobs

  ### Primary Options

  These options determine what the system does at a high level, i.e. which queues to run.

  * `:node` — used to identify the node that the supervision tree is running in. If no value is
    provided it will use the `node` name in a distributed system, or the `hostname` in an isolated
    node. See "Node Name" below.

  * `:plugins` — a list or modules or module/option tuples that are started as children of an Oban
    supervisor. Any supervisable module is a valid plugin, i.e. a `GenServer` or an `Agent`.

  * `:prefix` — the query prefix, or schema, to use for inserting and executing jobs. An
    `oban_jobs` table must exist within the prefix. See the "Prefix Support" section in the module
    documentation for more details.

  * `:queues` — a keyword list where the keys are queue names and the values are the concurrency
    setting or a keyword list of queue options. For example, setting queues to `[default: 10,
    exports: 5]` would start the queues `default` and `exports` with a combined concurrency level
    of 15. The concurrency setting specifies how many jobs _each queue_ will run concurrently.

    Queues accept additional override options to customize their behavior, e.g. by setting
    `paused` or `dispatch_cooldown` for a specific queue.

    For testing purposes `:queues` may be set to `false` or `nil`, which effectively disables all
    job dispatching.

  * `:log` — either `false` to disable logging or a standard log level (`:error`, `:warn`,
    `:info`, `:debug`). This determines whether queries are logged or not; overriding the repo's
    configured log level. Defaults to `false`, where no queries are logged.

  ### Twiddly Options

  Additional options used to tune system behaviour. These are primarily useful for testing or
  troubleshooting and don't usually need modification.

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

  * `:shutdown_grace_period` - the amount of time a queue will wait for executing jobs to complete
    before hard shutdown, specified in milliseconds. The default is `15_000`, or 15 seconds.

  ## Example

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

    Supervisor.start_link(__MODULE__, conf, name: Registry.via(conf.name, nil, conf))
  end

  @spec child_spec([option]) :: Supervisor.child_spec()
  def child_spec(opts) do
    opts
    |> super()
    |> Supervisor.child_spec(id: Keyword.get(opts, :name, __MODULE__))
  end

  @doc """
  Returns the pid of the root oban process for the given name.

  ## Example

  Find the default instance:

      Oban.whereis(Oban)

  Find a dynamically named instance:

      Oban.whereis({:oban, 1})
  """
  @doc since: "2.2.0"
  @spec whereis(name()) :: pid() | nil
  def whereis(name), do: Registry.whereis(name)

  @impl Supervisor
  def init(%Config{plugins: plugins, queues: queues} = conf) do
    children = [
      {Notifier, conf: conf, name: Registry.via(conf.name, Notifier)},
      {Midwife, conf: conf, name: Registry.via(conf.name, Midwife)}
    ]

    children = children ++ Enum.map(plugins, &plugin_child_spec(&1, conf))
    children = children ++ Enum.map(queues, &QueueSupervisor.child_spec(&1, conf))

    execute_init(conf)

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp plugin_child_spec({module, opts}, conf) do
    name = Registry.via(conf.name, {:plugin, module})

    opts =
      opts
      |> Keyword.put_new(:conf, conf)
      |> Keyword.put_new(:name, name)

    Supervisor.child_spec({module, opts}, id: {:plugin, module})
  end

  defp plugin_child_spec(module, conf) do
    plugin_child_spec({module, []}, conf)
  end

  defp execute_init(conf) do
    measurements = %{system_time: System.system_time()}
    metadata = %{pid: self(), conf: conf}

    Telemetry.execute([:oban, :supervisor, :init], measurements, metadata)
  end

  @doc """
  Retrieve the config struct for a named Oban supervision tree.
  """
  @doc since: "0.2.0"
  @spec config(name()) :: Config.t()
  def config(name \\ __MODULE__), do: Registry.config(name)

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
  @spec insert(name(), Job.changeset()) ::
          {:ok, Job.t()} | {:error, Job.changeset()} | {:error, term()}
  def insert(name \\ __MODULE__, %Changeset{} = changeset) do
    name
    |> config()
    |> Query.fetch_or_insert_job(changeset)
  end

  @doc """
  Put a job insert operation into an `Ecto.Multi`.

  Like `insert/2`, this variant is recommended over `Ecto.Multi.insert` because it supports all of
  Oban's features, i.e. unique jobs.

  See the section on "Unique Jobs" for more details.

  ## Example

      Ecto.Multi.new()
      |> Oban.insert("job-1", MyApp.Worker.new(%{id: 1}))
      |> Oban.insert("job-2", fn _ -> MyApp.Worker.new(%{id: 2}) end)
      |> MyApp.Repo.transaction()
  """
  @doc since: "0.7.0"
  @spec insert(
          name,
          multi :: Multi.t(),
          multi_name :: Multi.name(),
          changeset_or_fun :: Job.changeset() | Job.changeset_fun()
        ) :: Multi.t()
  def insert(name \\ __MODULE__, multi, multi_name, changeset_or_fun)

  def insert(name, %Multi{} = multi, multi_name, %Changeset{} = changeset) do
    name
    |> config()
    |> Query.fetch_or_insert_job(multi, multi_name, changeset)
  end

  def insert(name, %Multi{} = multi, multi_name, fun) when is_function(fun, 1) do
    name
    |> config()
    |> Query.fetch_or_insert_job(multi, multi_name, fun)
  end

  @doc """
  Similar to `insert/2`, but raises an `Ecto.InvalidChangesetError` if the job can't be inserted.

  ## Example

      job = Oban.insert!(MyApp.Worker.new(%{id: 1}))
  """
  @doc since: "0.7.0"
  @spec insert!(name(), Job.changeset()) :: Job.t()
  def insert!(name \\ __MODULE__, %Changeset{} = changeset) do
    case insert(name, changeset) do
      {:ok, job} ->
        job

      {:error, %Changeset{} = changeset} ->
        raise Ecto.InvalidChangesetError, action: :insert, changeset: changeset

      {:error, reason} ->
        raise RuntimeError, inspect(reason)
    end
  end

  @doc """
  Insert multiple jobs into the database for execution.

  Insertion respects `prefix` and `log` settings, but it *does not use* per-job unique
  configuration. You must use `insert/2,4` or `insert!/2` for per-job unique support.

  There are a few important differences between this function and `c:Ecto.Repo.insert_all/3`:

  1. This function always returns a list rather than a tuple of `{count, records}`
  2. This function requires a list of changesets rather than a list of maps or keyword lists

  ## Example

      1..100
      |> Enum.map(&MyApp.Worker.new(%{id: &1}))
      |> Oban.insert_all()
  """
  @doc since: "0.9.0"
  @spec insert_all(name(), changesets_or_wrapper()) :: [Job.t()]
  def insert_all(name \\ __MODULE__, changesets_or_wrapper)

  def insert_all(name, %{changesets: [_ | _] = changesets}) do
    insert_all(name, changesets)
  end

  def insert_all(name, changesets) when is_list(changesets) do
    name
    |> config()
    |> Query.insert_all_jobs(changesets)
  end

  @doc """
  Put an `insert_all` operation into an `Ecto.Multi`.

  This function supports the same features and has the same caveats as `insert_all/2`.

  ## Example

      changesets = Enum.map(0..100, &MyApp.Worker.new(%{id: &1}))

      Ecto.Multi.new()
      |> Oban.insert_all(:jobs, changesets)
      |> MyApp.Repo.transaction()
  """
  @doc since: "0.9.0"
  @spec insert_all(
          name(),
          multi :: Multi.t(),
          multi_name :: Multi.name(),
          changesets_or_wrapper() | Job.changeset_list_fun()
        ) :: Multi.t()
  def insert_all(name \\ __MODULE__, multi, multi_name, changesets_or_wrapper)

  def insert_all(name, multi, multi_name, %{changesets: [_ | _] = changesets}) do
    insert_all(name, multi, multi_name, changesets)
  end

  def insert_all(name, %Multi{} = multi, multi_name, changesets)
      when is_list(changesets) or is_function(changesets, 1) do
    name
    |> config()
    |> Query.insert_all_jobs(multi, multi_name, changesets)
  end

  @doc """
  Synchronously execute all available jobs in a queue.

  All execution happens within the current process and it is guaranteed not to raise an error or
  exit.

  Draining a queue from within the current process is especially useful for testing. Jobs that are
  enqueued by a process when `Ecto` is in sandbox mode are only visible to that process. Calling
  `drain_queue/2` allows you to control when the jobs are executed and to wait synchronously for
  all jobs to complete.

  ## Failures & Retries

  Draining a queue uses the same execution mechanism as regular job dispatch. That means that any
  job failures or crashes are captured and result in a retry. Retries are scheduled in the future
  with backoff and won't be retried immediately.

  By default jobs are executed in `safe` mode, just as they are in production. Safe mode catches
  any errors or exits and records the formatted error in the job's `errors` array.  That means
  exceptions and crashes are _not_ bubbled up to the calling process.

  If you expect jobs to fail, would like to track failures, or need to check for specific errors
  you can pass the `with_safety: false` flag.

  ## Scheduled Jobs

  By default, `drain_queue/2` will execute all currently available jobs. In order to execute
  scheduled jobs, you may pass the `:with_scheduled` flag which will cause scheduled jobs to be
  marked as `available` beforehand.

  ## Options

  * `:queue` - a string or atom specifying the queue to drain, required
  * `:with_scheduled` — whether to include any scheduled jobs when draining, default `false`
  * `:with_safety` — whether to silently catch errors when draining, default `true`

  ## Example

  Drain a queue with three available jobs, two of which succeed and one of which fails:

      Oban.drain_queue(queue: :default)
      %{success: 2, failure: 1}

  Drain a queue including any scheduled jobs:

      Oban.drain_queue(queue: :default, with_scheduled: true)
      %{success: 1, failure: 0}

  Drain a queue and assert an error is raised:

      assert_raise RuntimeError, fn -> Oban.drain_queue(queue: :risky, with_safety: false) end
  """
  @doc since: "0.4.0"
  @spec drain_queue(name(), [drain_option()]) :: drain_result()
  def drain_queue(name \\ __MODULE__, [_ | _] = opts) do
    name
    |> config()
    |> Drainer.drain(opts)
  end

  @doc """
  Start a new supervised queue.

  By default this starts a new supervised queue across all nodes running Oban on the same database
  and prefix. You can pass the option `local_only: true` if you prefer to start the queue only on
  the local node.

  ## Options

  * `:queue` - a string or atom specifying the queue to start, required
  * `:limit` - set the concurrency limit, required
  * `:local_only` - whether the queue will be started only on the local node, default: `false`

  ## Example

  Start the `:priority` queue with a concurrency limit of 10 across the connected nodes.

      Oban.start_queue(queue: :priority, limit: 10)
      :ok

  Start the `:media` queue with a concurrency limit of 5 only on the local node.

      Oban.start_queue(queue: :media, limit: 5, local_only: true)
      :ok
  """
  @doc since: "0.12.0"
  @spec start_queue(name(), opts :: [queue_option()]) :: :ok
  def start_queue(name \\ __MODULE__, [_ | _] = opts) do
    Enum.each(opts, &validate_queue_opt!/1)

    conf = config(name)

    data = %{
      action: :start,
      queue: opts[:queue],
      limit: opts[:limit],
      ident: scope_signal(conf, opts)
    }

    Notifier.notify(conf, :signal, data)
  end

  @doc """
  Pause a running queue, preventing it from executing any new jobs. All running jobs will remain
  running until they are finished.

  When shutdown begins all queues are paused.

  ## Options

  * `:queue` - a string or atom specifying the queue to pause, required
  * `:local_only` - whether the queue will be paused only on the local node, default: `false`

  ## Example

  Pause the default queue:

      Oban.pause_queue(queue: :default)
      :ok

  Pause the default queue, but only on the local node:

      Oban.pause_queue(queue: :default, local_only: true)
      :ok
  """
  @doc since: "0.2.0"
  @spec pause_queue(name(), opts :: [queue_option()]) :: :ok
  def pause_queue(name \\ __MODULE__, [_ | _] = opts) do
    Enum.each(opts, &validate_queue_opt!/1)

    conf = config(name)
    data = %{action: :pause, queue: opts[:queue], ident: scope_signal(conf, opts)}

    Notifier.notify(conf, :signal, data)
  end

  @doc """
  Resume executing jobs in a paused queue.

  ## Options

  * `:queue` - a string or atom specifying the queue to resume, required
  * `:local_only` - whether the queue will be resumed only on the local node, default: `false`

  ## Example

  Resume a paused default queue:

      Oban.resume_queue(:default)
      :ok

  Resume the default queue, but only on the local node:

      Oban.resume_queue(queue: :default, local_only: true)
      :ok
  """
  @doc since: "0.2.0"
  @spec resume_queue(name(), opts :: [queue_option()]) :: :ok
  def resume_queue(name \\ __MODULE__, [_ | _] = opts) do
    Enum.each(opts, &validate_queue_opt!/1)

    conf = config(name)
    data = %{action: :resume, queue: opts[:queue], ident: scope_signal(conf, opts)}

    Notifier.notify(conf, :signal, data)
  end

  @doc """
  Scale the concurrency for a queue.

  ## Options

  * `:queue` - a string or atom specifying the queue to scale, required
  * `:limit` — the new concurrency limit
  * `:local_only` — whether the queue will be scaled only on the local node, default: `false`

  ## Example

  Scale a queue up, triggering immediate execution of queued jobs:

      Oban.scale_queue(queue: :default, limit: 50)
      :ok

  Scale the queue back down, allowing executing jobs to finish:

      Oban.scale_queue(queue: :default, limit: 5)
      :ok

  Scale the queue only on the local node:

      Oban.scale_queue(queue: :default, limit: 10, local_only: true)
      :ok
  """
  @doc since: "0.2.0"
  @spec scale_queue(name(), opts :: [queue_option()]) :: :ok
  def scale_queue(name \\ __MODULE__, [_ | _] = opts) do
    Enum.each(opts, &validate_queue_opt!/1)

    conf = config(name)

    data = %{
      action: :scale,
      queue: opts[:queue],
      limit: opts[:limit],
      ident: scope_signal(conf, opts)
    }

    Notifier.notify(conf, :signal, data)
  end

  @doc """
  Shutdown a queue's supervision tree and stop running jobs for that queue.

  By default this action will occur across all the running nodes. Still, if you prefer to stop the
  queue's supervision tree and stop running jobs for that queue only on the local node, you can
  pass the option: `local_only: true`

  The shutdown process pauses the queue first and allows current jobs to exit gracefully, provided
  they finish within the shutdown limit.

  ## Options

  * `:queue` - a string or atom specifying the queue to stop, required
  * `:local_only` - whether the queue will be stopped only on the local node, default: `false`

  ## Example

      Oban.stop_queue(queue: :default)
      :ok

      Oban.stop_queue(queue: :media, local_only: true)
      :ok
  """
  @doc since: "0.12.0"
  @spec stop_queue(name(), opts :: [queue_option()]) :: :ok
  def stop_queue(name \\ __MODULE__, [_ | _] = opts) do
    Enum.each(opts, &validate_queue_opt!/1)

    conf = config(name)
    data = %{action: :stop, queue: opts[:queue], ident: scope_signal(conf, opts)}

    Notifier.notify(conf, :signal, data)
  end

  @doc """
  Check the current state of a queue producer.

  This allows you to introspect on a queue's health by retrieving key attributes of the producer's
  state; values such as the current `limit`, the `running` job ids, and when the producer was
  started.

  ## Options

  * `:queue` - a string or atom specifying the queue to check, required

  ## Example

      Oban.check_queue(queue: :default)
      %{
        limit: 10,
        node: "me@local",
        nonce: "a1b2c3d4",
        paused: false,
        queue: "default",
        running: [100, 102],
        started_at: ~D[2020-10-07 15:31:00]
      }
  """
  @doc since: "2.2.0"
  @spec check_queue(name(), opts :: [{:queue, queue_name()}]) :: queue_state()
  def check_queue(name \\ __MODULE__, [_ | _] = opts) do
    Enum.each(opts, &validate_queue_opt!/1)

    name
    |> Registry.via({:producer, to_string(opts[:queue])})
    |> Producer.check()
  end

  @doc """
  Sets a job as `available`, adding attempts if already maxed out. If the job is currently
  `available`, `executing` or `scheduled` it will be ignored. The job is scheduled for immediate
  execution.

  ## Example

  Retry a discarded job with the id `1`:

      Oban.retry_job(1)
      :ok
  """
  @doc since: "2.2.0"
  @spec retry_job(name :: atom(), job_id :: pos_integer()) :: :ok
  def retry_job(name \\ __MODULE__, job_id) when is_integer(job_id) do
    name
    |> config()
    |> Query.retry_job(job_id)
  end

  @doc """
  Cancel an `available`, `scheduled` or `retryable` job and mark it as `discarded` to prevent it
  from running. If the job is currently `executing` it will be killed and otherwise it is ignored.

  If an executing job happens to fail before it can be cancelled the state is set to `discarded`.
  However, if it manages to complete successfully then the state will still be `completed`.

  ## Example

  Cancel a scheduled job with the id `1`:

      Oban.cancel_job(1)
      :ok
  """
  @doc since: "1.3.0"
  @spec cancel_job(name(), job_id :: pos_integer()) :: :ok
  def cancel_job(name \\ __MODULE__, job_id) when is_integer(job_id) do
    conf = config(name)

    Query.cancel_job(conf, job_id)
    Notifier.notify(conf, :signal, %{action: :pkill, job_id: job_id})
  end

  defp scope_signal(conf, opts) do
    if Keyword.get(opts, :local_only) do
      Config.to_ident(conf)
    else
      :any
    end
  end

  defp validate_queue_opt!({:queue, queue}) do
    unless (is_atom(queue) and not is_nil(queue)) or (is_binary(queue) and byte_size(queue) > 0) do
      raise ArgumentError,
            "expected :queue to be a binary or atom (except `nil`), got: #{inspect(queue)}"
    end
  end

  defp validate_queue_opt!({:limit, limit}) do
    unless is_integer(limit) and limit > 0 do
      raise ArgumentError, "expected :limit to be a positive integer, got: #{inspect(limit)}"
    end
  end

  defp validate_queue_opt!({:local_only, local_only}) do
    unless is_boolean(local_only) do
      raise ArgumentError, "expected :local_only to be a boolean, got: #{inspect(local_only)}"
    end
  end

  defp validate_queue_opt!(option) do
    raise ArgumentError, "unknown option provided #{inspect(option)}"
  end
end
