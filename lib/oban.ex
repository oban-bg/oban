defmodule Oban do
  @external_resource readme = Path.join([__DIR__, "../README.md"])

  @doc_header """
  Oban is a robust job processing library which uses PostgreSQL or SQLite3 for persistence.

  > #### Oban Web+Pro {: .tip}
  >
  > A web dashboard for managing Oban, along with an official set of extensions, plugins, and
  > workers that expand what Oban is capable of are available as licensed packages:
  > 
  > * [🧭 Oban Web](https://getoban.pro#oban-web)
  > * [🌟 Oban Pro](https://getoban.pro#oban-pro)
  > 
  > Learn more at [getoban.pro][pro]!

  """

  @doc_footer readme
              |> File.read!()
              |> String.split("<!-- MDOC -->")
              |> Enum.fetch!(1)

  @moduledoc @doc_header <> @doc_footer

  use Supervisor

  alias Ecto.{Changeset, Multi}
  alias Oban.{Config, Engine, Job, Midwife, Notifier, Peer, Registry, Sonar, Stager}
  alias Oban.Queue.{Drainer, Producer}

  @typedoc """
  The name of an Oban instance. This is used to identify instances in the internal registry for
  configuration lookup.
  """
  @type name :: term()

  @type oban_node :: String.t()

  @type queue_name :: atom() | binary()

  @type queue_option ::
          {:local_only, boolean()}
          | {:node, oban_node()}
          | {:queue, queue_name()}

  @type queue_all_option :: {:local_only, boolean()} | {:node, oban_node()}

  @type queue_state :: %{
          :limit => pos_integer(),
          :node => oban_node(),
          :paused => boolean(),
          :queue => queue_name(),
          :running => [pos_integer()],
          :started_at => DateTime.t(),
          :updated_at => DateTime.t(),
          optional(atom()) => any()
        }

  @type option ::
          {:dispatch_cooldown, pos_integer()}
          | {:engine, module()}
          | {:get_dynamic_repo, nil | (-> pid() | atom())}
          | {:log, false | Logger.level()}
          | {:name, name()}
          | {:node, oban_node()}
          | {:notifier, module() | {module(), Keyword.t()}}
          | {:peer, false | module() | {module(), Keyword.t()}}
          | {:plugins, false | [module() | {module() | Keyword.t()}]}
          | {:prefix, false | String.t()}
          | {:queues, false | [{queue_name(), pos_integer() | Keyword.t()}]}
          | {:repo, module()}
          | {:shutdown_grace_period, non_neg_integer()}
          | {:stage_interval, timeout()}
          | {:testing, :disabled | :inline | :manual}

  @type drain_option ::
          {:queue, queue_name()}
          | {:with_limit, pos_integer()}
          | {:with_recursion, boolean()}
          | {:with_safety, boolean()}
          | {:with_scheduled, boolean() | DateTime.t()}

  @type drain_result :: %{
          cancelled: non_neg_integer(),
          discard: non_neg_integer(),
          failure: non_neg_integer(),
          snoozed: non_neg_integer(),
          success: non_neg_integer()
        }

  @type changeset_or_fun :: Job.changeset() | Job.changeset_fun()
  @type changesets_or_wrapper :: Job.changeset_list() | changeset_wrapper()
  @type changesets_or_wrapper_or_fun :: changesets_or_wrapper() | Job.changeset_list_fun()
  @type changeset_wrapper :: %{:changesets => Job.changeset_list(), optional(atom()) => term()}
  @type multi :: Multi.t()
  @type multi_name :: Multi.name()

  defguardp is_changeset_or_fun(cf)
            when is_struct(cf, Changeset) or is_function(cf, 1)

  defguardp is_list_or_wrapper(cw)
            when is_list(cw) or
                   is_struct(cw, Stream) or
                   is_function(cw, 1) or
                   (is_map_key(cw, :changesets) and is_list(cw.changesets)) or
                   (is_map_key(cw, :changesets) and is_struct(cw.changesets, Stream)) or
                   (is_map_key(cw, :changesets) and is_function(cw.changesets))

  @doc """
  Creates a facade for `Oban` functions and automates fetching configuration from the application
  environment.

  Facade modules support configuration via the application environment under an OTP application
  key. For example, the facade:

      defmodule MyApp.Oban do
        use Oban, otp_app: MyApp
      end

  Could be configured with:

      config :my_app, Oban, repo: MyApp.Repo

  Then you can include `MyApp.Oban` in your application's supervision tree without passing extra
  options:

      defmodule MyApp.Application do
        use Application

        def start(_type, _args) do
          children = [
            MyApp.Repo,
            MyApp.Oban
          ]

          opts = [strategy: :one_for_one, name: MyApp.Supervisor]
          Supervisor.start_link(children, opts)
        end
      end

  ### Calling Functions

  Facade modules allow you to call `Oban` functions on instances with custom names, e.g. not
  `Oban`, without passing a `t:Oban.name/0` as the first argument.

  For example, rather than calling `Oban.config/1` you'd call `MyOban.config/0`:

      MyOban.config()

  It also makes piping into Oban functions far more convenient:

      %{some: :args}
      |> MyWorker.new()
      |> MyOban.insert()

  ### Merging Configuration

  All configuration can be provided through the `use` macro or application config, and options
  from the application supersedes those passed through `use`. Configuration is prioritized in
  order:

  1. Options passed through `use`
  2. Options pulled from the OTP app via `Application.get_env/3`
  3. Options passed through a child spec in the supervisor
  """
  defmacro __using__(opts \\ []) do
    {otp_app, child_opts} = Keyword.pop!(opts, :otp_app)

    quote do
      def child_spec(opts) do
        unquote(child_opts)
        |> Keyword.merge(Application.get_env(unquote(otp_app), __MODULE__, []))
        |> Keyword.merge(opts)
        |> Keyword.put(:name, __MODULE__)
        |> Oban.child_spec()
      end

      def cancel_all_jobs(queryable) do
        Oban.cancel_all_jobs(__MODULE__, queryable)
      end

      def cancel_job(job_or_id) do
        Oban.cancel_job(__MODULE__, job_or_id)
      end

      def check_queue(opts) do
        Oban.check_queue(__MODULE__, opts)
      end

      def config do
        Oban.config(__MODULE__)
      end

      def drain_queue(opts) do
        Oban.drain_queue(__MODULE__, opts)
      end

      def insert(changeset, opts \\ []) do
        Oban.insert(__MODULE__, changeset, opts)
      end

      def insert(multi, multi_name, changeset, opts \\ []) do
        Oban.insert(__MODULE__, multi, multi_name, changeset, opts)
      end

      def insert!(changeset, opts \\ []) do
        Oban.insert!(__MODULE__, changeset, opts)
      end

      def insert_all(changesets, opts) do
        Oban.insert_all(__MODULE__, changesets, opts)
      end

      def insert_all(multi, multi_name, changesets, opts) do
        Oban.insert_all(__MODULE__, multi, multi_name, changesets, opts)
      end

      def start_queue(opts) do
        Oban.start_queue(__MODULE__, opts)
      end

      def pause_queue(opts) do
        Oban.pause_queue(__MODULE__, opts)
      end

      def pause_all_queues(opts \\ []) do
        Oban.pause_all_queues(__MODULE__, opts)
      end

      def resume_queue(opts) do
        Oban.resume_queue(__MODULE__, opts)
      end

      def resume_all_queues(opts \\ []) do
        Oban.resume_all_queues(__MODULE__, opts)
      end

      def scale_queue(opts) do
        Oban.scale_queue(__MODULE__, opts)
      end

      def stop_queue(opts) do
        Oban.stop_queue(__MODULE__, opts)
      end

      def retry_job(job_or_id) do
        Oban.retry_job(__MODULE__, job_or_id)
      end

      def retry_all_jobs(queryable) do
        Oban.retry_all_jobs(__MODULE__, queryable)
      end

      defoverridable cancel_all_jobs: 1,
                     cancel_job: 1,
                     check_queue: 1,
                     config: 0,
                     drain_queue: 1,
                     insert: 2,
                     insert: 4,
                     insert!: 2,
                     insert_all: 2,
                     insert_all: 4,
                     start_queue: 1,
                     pause_queue: 1,
                     pause_all_queues: 1,
                     resume_queue: 1,
                     resume_all_queues: 1,
                     scale_queue: 1,
                     stop_queue: 1,
                     retry_job: 1,
                     retry_all_jobs: 1
    end
  end

  @doc """
  Starts an `Oban` supervision tree linked to the current process.

  ## Options

  These options are required; without them the supervisor won't start:

  * `:repo` — specifies the Ecto repo used to insert and retrieve jobs

  ### Primary Options

  These options determine what the system does at a high level, i.e. which queues to run:

  * `:engine` — facilitates inserting, fetching, and otherwise managing jobs.

    There are three built-in engines: `Oban.Engines.Basic` for Postgres databases,
    `Oban.Engines.Lite` for SQLite3 databases, and `Oban.Engines.Inline` for simplified testing
    (only available for `:inline` testing mode).

    When the `Oban.Engines.Lite` engine is used the `:notifier` and `:peer` are automatically set
    to `PG` and `isolated` mode, respectively.

    Additional engines, such as Oban Pro's `SmartEngine` with advanced functionality for Postgres,
    are also available as an add-on.

    Defaults to the `Basic` engine for Postgres.

  * `:log` — either `false` to disable logging or a standard log level (`:error`, `:warning`,
    `:info`, `:debug`, etc.). This determines whether queries are logged or not; overriding the
    repo's configured log level. Defaults to `false`, where no queries are logged.

  * `:name` — used for supervisor registration, it must be unique across an entire VM instance.
    Defaults to `Oban` when no name is provided.

  * `:node` — used to identify the node that the supervision tree is running in. If no value is
    provided it will use the `node` name in a distributed system, or the `hostname` in an isolated
    node. See "Node Name" below.

  * `:notifier` — used to relay messages between processes, nodes, and the Postgres database.

    There are two built-in notifiers: `Oban.Notifiers.Postgres`, which uses Postgres PubSub; and
    `Oban.Notifiers.PG`, which uses process groups with distributed erlang. Defaults to the
    Postgres notifier.

  * `:peer` — used to specify which peer module to use for cluster leadership.

    There are two built-in peers: `Oban.Peers.Postgres`, which uses table-based leadership through
    the `oban_peers` table; and `Oban.Peers.Global`, which uses global locks through distributed Erlang.

    Leadership can be disabled by setting `peer: false`, but note that centralized plugins like
    `Cron` won't run without leadership.

    Defaults to the `Postgres` peer.

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

  * `:testing` — a mode that controls how an instance is configured for testing. When set to
    `:inline` or `:manual` queues, peers, and plugins are automatically disabled. Defaults to
    `:disabled`, no test mode.

  ### Twiddly Options

  Additional options used to tune system behaviour. These are primarily useful for testing or
  troubleshooting and don't usually need modification.

  * `:dispatch_cooldown` — the minimum number of milliseconds a producer will wait before fetching
    and running more jobs. A slight cooldown period prevents a producer from flooding with
    messages and thrashing the database. The cooldown period _directly impacts_ a producer's
    throughput: jobs per second for a single queue is calculated by `(1000 / cooldown) * limit`.
    For example, with a `5ms` cooldown and a queue limit of `25` a single queue can run 5,000
    jobs/sec.

    The default is `5ms` and the minimum is `1ms`, which is likely faster than the database can
    return new jobs to run.

  * `:insert_trigger` — whether to dispatch notifications to relevant queues as jobs are inserted
    into the database. At high load, e.g. thousands or more job inserts per second, notifications
    may become a bottleneck.

    The trigger mechanism is designed to make jobs execute immediately after insert, rather than
    up to `:stage_interval` (1 second) afterwards, and it can safely be disabled to improve insert
    throughput.

    Defaults to `true`, with triggering enabled.

  * `:shutdown_grace_period` — the amount of time a queue will wait for executing jobs to complete
    before hard shutdown, specified in milliseconds. The default is `15_000`, or 15 seconds.

  * `:stage_interval` — the number of milliseconds between making scheduled jobs available and
    notifying relevant queues that jobs are available. This is directly tied to the resolution of
    `scheduled` or `retryable` jobs and how frequently the database is checked for jobs to run. To
    minimize database load, only `5_000` jobs are staged at each interval.

    Only the leader node stages jobs and notifies queues when the `:notifier's` pubsub
    notifications are functional. If pubusb messages can't get through then staging switches to a
    less efficient "local" mode in which all nodes poll for jobs to run.

    Setting the interval to `:infinity` disables staging entirely. The default is `1_000ms`.

  ## Example

  Start a stand-alone `Oban` instance:

      {:ok, pid} = Oban.start_link(repo: MyApp.Repo, queues: [default: 10])

  To start an `Oban` instance within an application's supervision tree:

      def start(_type, _args) do
        children = [MyApp.Repo, {Oban, repo: MyApp.Repo, queues: [default: 10]}]

        Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)
      end

  Start multiple, named `Oban` supervisors within a supervision tree:

        children = [
          MyApp.Repo,
          {Oban, name: Oban.A, repo: MyApp.Repo, queues: [default: 10]},
          {Oban, name: Oban.B, repo: MyApp.Repo, queues: [special: 10]},
        ]

        Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)

  Start a local `Oban` instance for SQLite:

      {:ok, pid} = Oban.start_link(engine: Oban.Engines.Lite, repo: MyApp.Repo)

  ## Node Name

  When the `node` value has not been configured it is generated based on the environment:

  1. If the local node is alive (e.g. in a distributed system, or when running from a mix release)
     the node name is used
  2. In a Heroku environment the system environment's `DYNO` value is used
  3. Otherwise, the system hostname is used

  When running a mix release on a Heroku node, the node is alive even if not part of a
  distributed system. In order to use the `DYNO` value, configure the node value using runtime
  configuration via `config/runtime.exs`:

        config :my_app, Oban,
          node: System.get_env("DYNO", "nonode@nohost")

  """
  @doc since: "0.1.0"
  @spec start_link([option()]) :: Supervisor.on_start()
  def start_link(opts) when is_list(opts) do
    conf = Config.new(opts)

    Supervisor.start_link(__MODULE__, conf, name: Registry.via(conf.name, nil, conf))
  end

  @doc false
  @spec child_spec([option]) :: Supervisor.child_spec()
  def child_spec(opts) do
    opts
    |> super()
    |> Supervisor.child_spec(id: Keyword.get(opts, :name, __MODULE__))
  end

  @doc """
  Returns the pid of the root Oban process for the given name.

  ## Example

  Find the default instance:

      Oban.whereis(Oban)

  Find a dynamically named instance:

      Oban.whereis({:oban, 1})
  """
  @doc since: "2.2.0"
  @spec whereis(name()) :: pid() | {atom(), node()} | nil
  def whereis(name), do: Registry.whereis(name)

  @impl Supervisor
  def init(%Config{plugins: plugins} = conf) do
    children = [
      {Notifier, conf: conf, name: Registry.via(conf.name, Notifier)},
      {DynamicSupervisor, name: Registry.via(conf.name, Foreman), strategy: :one_for_one},
      {Peer, conf: conf, name: Registry.via(conf.name, Peer)},
      {Sonar, conf: conf, name: Registry.via(conf.name, Sonar)},
      {Midwife, conf: conf, name: Registry.via(conf.name, Midwife)},
      {Stager, conf: conf, name: Registry.via(conf.name, Stager)}
    ]

    children = children ++ Enum.map(plugins, &plugin_child_spec(&1, conf))
    children = children ++ event_child_spec(conf)

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Retrieve the `Oban.Config` struct for a named Oban supervision tree.

  ## Example

  Retrieve the default `Oban` instance config:

      %Oban.Config{} = Oban.config()

  Retrieve the config for an instance started with a custom name:

      %Oban.Config{} = Oban.config(MyCustomOban)
  """
  @doc since: "0.2.0"
  @spec config(name()) :: Config.t()
  def config(name \\ __MODULE__), do: Registry.config(name)

  @doc false
  def insert(%Changeset{} = changeset, opts) do
    insert(__MODULE__, changeset, opts)
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

  Insert a job using a custom timeout:

      {:ok, job} = Oban.insert(MyApp.Worker.new(%{id: 1}), timeout: 10_000)

  Insert a job using an alternative instance name:

      {:ok, job} = Oban.insert(MyOban, MyApp.Worker.new(%{id: 1}))
  """
  @doc since: "0.7.0"
  @spec insert(name(), Job.changeset(), Keyword.t()) ::
          {:ok, Job.t()} | {:error, Job.changeset() | term()}
  def insert(name \\ __MODULE__, changeset, opts \\ [])

  def insert(name, %Changeset{} = changeset, opts) do
    name
    |> config()
    |> Engine.insert_job(changeset, opts)
  end

  @spec insert(multi(), multi_name(), changeset_or_fun()) :: multi()
  def insert(%Multi{} = multi, multi_name, changeset) when is_changeset_or_fun(changeset) do
    insert(__MODULE__, multi, multi_name, changeset, [])
  end

  @doc false
  def insert(%Multi{} = multi, multi_name, changeset, opts) when is_changeset_or_fun(changeset) do
    insert(__MODULE__, multi, multi_name, changeset, opts)
  end

  @doc false
  def insert(name, multi, multi_name, changeset) when is_changeset_or_fun(changeset) do
    insert(name, multi, multi_name, changeset, [])
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
  @spec insert(name, multi(), multi_name(), changeset_or_fun(), Keyword.t()) :: multi()
  def insert(name, multi, multi_name, changeset, opts)
      when is_changeset_or_fun(changeset) and is_list(opts) do
    name
    |> config()
    |> Engine.insert_job(multi, multi_name, changeset, opts)
  end

  @doc false
  @spec insert!(Job.changeset(), opts :: Keyword.t()) :: Job.t()
  def insert!(%Changeset{} = changeset, opts) do
    insert!(__MODULE__, changeset, opts)
  end

  @doc """
  Similar to `insert/3`, but raises an `Ecto.InvalidChangesetError` if the job can't be inserted.

  ## Example

  Insert a single job:

      job = Oban.insert!(MyApp.Worker.new(%{id: 1}))

  Insert a job using a custom timeout:

      job = Oban.insert!(MyApp.Worker.new(%{id: 1}), timeout: 10_000)

  Insert a job using an alternative instance name:

      job = Oban.insert!(MyOban, MyApp.Worker.new(%{id: 1}))
  """
  @doc since: "0.7.0"
  @spec insert!(name(), Job.changeset()) :: Job.t()
  @spec insert!(name(), Job.changeset(), opts :: Keyword.t()) :: Job.t()
  def insert!(name \\ __MODULE__, %Changeset{} = changeset, opts \\ []) do
    case insert(name, changeset, opts) do
      {:ok, job} ->
        job

      {:error, %Changeset{} = changeset} ->
        raise Ecto.InvalidChangesetError, action: :insert, changeset: changeset

      {:error, reason} ->
        raise RuntimeError, inspect(reason)
    end
  end

  @doc false
  def insert_all(changesets, opts) when is_list_or_wrapper(changesets) do
    insert_all(__MODULE__, changesets, opts)
  end

  @doc """
  Insert multiple jobs into the database for execution.

  There are a few important differences between this function and `c:Ecto.Repo.insert_all/3`:

  1. This function always returns a list rather than a tuple of `{count, records}`
  2. This function accepts a list of changesets rather than a list of maps or keyword lists

  #### Error Handling and Rollbacks

  If `insert_all` encounters an issue, the function will raise an error based on your database
  adapter. This behavior is valuable in conjunction with `c:Ecto.Repo.transaction/2` because it
  allows for rollbacks.

  For example, an invalid changeset raises:

  `* (Ecto.InvalidChangesetError) could not perform insert because changeset is invalid.`

  > #### 🌟 Unique Jobs and Batching {: .warning}
  >
  > Only the [Smart Engine](https://getoban.pro/docs/pro/Oban.Pro.Engines.Smart.html) in [Oban
  > Pro](https://getoban.pro) supports bulk unique jobs and automatic batching. With the basic
  > engine, you must use `insert/3` for unique support.

  ## Options

  Accepts any of Ecto's "Shared Options" such as `timeout` and `log`.

  ## Example

  Insert a list of 100 jobs at once:

      1..100
      |> Enum.map(&MyApp.Worker.new(%{id: &1}))
      |> Oban.insert_all()

  Insert a stream of jobs at once (be sure the stream terminates!):

      (fn -> MyApp.Worker.new(%{}))
      |> Stream.repeatedly()
      |> Stream.take(100)
      |> Oban.insert_all()

  Insert with a custom timeout:

      1..100
      |> Enum.map(&MyApp.Worker.new(%{id: &1}))
      |> Oban.insert_all(timeout: 10_000)

  Insert with an alternative instance name:

      changesets = Enum.map(1..100, &MyApp.Worker.new(%{id: &1}))
      jobs = Oban.insert_all(MyOban, changesets)
  """
  @doc since: "0.9.0"
  @spec insert_all(
          name() | multi(),
          changesets_or_wrapper() | multi_name(),
          Keyword.t() | changesets_or_wrapper_or_fun()
        ) :: [Job.t()] | multi()
  def insert_all(name \\ __MODULE__, changesets, opts \\ [])

  def insert_all(name, changesets, opts) when is_list_or_wrapper(changesets) and is_list(opts) do
    name
    |> config()
    |> Engine.insert_all_jobs(changesets, opts)
  end

  def insert_all(%Multi{} = multi, multi_name, changesets) when is_list_or_wrapper(changesets) do
    insert_all(__MODULE__, multi, multi_name, changesets, [])
  end

  @doc false
  def insert_all(%Multi{} = multi, multi_name, changesets, opts)
      when is_list_or_wrapper(changesets) do
    insert_all(__MODULE__, multi, multi_name, changesets, opts)
  end

  @doc false
  def insert_all(name, multi, multi_name, changesets) when is_list_or_wrapper(changesets) do
    insert_all(name, multi, multi_name, changesets, [])
  end

  @doc """
  Put an `insert_all` operation into an `Ecto.Multi`.

  This function supports the same features and has the same caveats as `insert_all/2`.

  ## Example

  Insert job changesets within a multi:

      changesets = Enum.map(0..100, &MyApp.Worker.new(%{id: &1}))

      Ecto.Multi.new()
      |> Oban.insert_all(:jobs, changesets)
      |> MyApp.Repo.transaction()

  Insert job changesets using a function:

      Ecto.Multi.new()
      |> Ecto.Multi.insert(:user, user_changeset)
      |> Oban.insert_all(:jobs, fn %{user: user} ->
        email_job = EmailWorker.new(%{id: user.id})
        staff_job = StaffWorker.new(%{id: user.id})
        [email_job, staff_job]
      end)
      |> MyApp.Repo.transaction()
  """
  @doc since: "0.9.0"
  @spec insert_all(name(), multi(), multi_name(), changesets_or_wrapper_or_fun(), Keyword.t()) ::
          multi()
  def insert_all(name, multi, multi_name, changesets, opts)
      when is_list_or_wrapper(changesets) and is_list(opts) do
    name
    |> config()
    |> Engine.insert_all_jobs(multi, multi_name, changesets, opts)
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
  you can pass the `with_safety: false` flag. See the "Options" section below for more details.

  ## Scheduled Jobs

  By default, `drain_queue/2` will execute all currently available jobs. In order to execute
  scheduled jobs, you may pass the `with_scheduled: true` which will cause all scheduled jobs to
  be marked as `available` beforehand. To run jobs scheduled up to a specific point in time, pass
  a `DateTime` instead.

  ## Options

  * `:queue` - a string or atom specifying the queue to drain, required

  * `:with_limit` — the maximum number of jobs to drain at once. When recursion is enabled this is
    how many jobs are processed per-iteration.

  * `:with_recursion` — whether to keep draining a queue repeatedly when jobs insert _more_ jobs

  * `:with_safety` — whether to silently catch errors when draining, defaults to `true`. When
    `false`, raised exceptions or unhandled exits are reraised (unhandled exits are wrapped in
    `Oban.CrashError`).

  * `:with_scheduled` — whether to include any scheduled jobs when draining, default `false`.
     When `true`, drains all scheduled jobs. When a `DateTime` is provided, drains all jobs
     scheduled up to, and including, that point in time.

  ## Example

  Drain a queue with three available jobs, two of which succeed and one of which fails:

      Oban.drain_queue(queue: :default)
      %{failure: 1, snoozed: 0, success: 2}

  Drain a queue including any scheduled jobs:

      Oban.drain_queue(queue: :default, with_scheduled: true)
      %{failure: 0, snoozed: 0, success: 1}

  Drain a queue including jobs scheduled up to a minute:

      Oban.drain_queue(queue: :default, with_scheduled: DateTime.add(DateTime.utc_now(), 60, :second))

  Drain a queue and assert an error is raised:

      assert_raise RuntimeError, fn -> Oban.drain_queue(queue: :risky, with_safety: false) end

  Drain a queue repeatedly until there aren't any more jobs to run. This is particularly useful
  for testing jobs that enqueue other jobs:

      Oban.drain_queue(queue: :default, with_recursion: true)
      %{failure: 1, snoozed: 0, success: 2}

  Drain only the top (by scheduled time and priority) five jobs off a queue:

      Oban.drain_queue(queue: :default, with_limit: 5)
      %{failure: 0, snoozed: 0, success: 1}

  Drain a queue recursively, only one job at a time:

      Oban.drain_queue(queue: :default, with_limit: 1, with_recursion: true)
      %{failure: 0, snoozed: 0, success: 3}
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
  * `:local_only` - whether the queue will be started only on the local node, default: `false`
  * `:limit` - set the concurrency limit, required
  * `:paused` — set whether the queue starts in the "paused" state, optional

  In addition, all engine-specific queue options are passed along after validation.

  ## Example

  Start the `:priority` queue with a concurrency limit of 10 across the connected nodes.

      Oban.start_queue(queue: :priority, limit: 10)
      :ok

  Start the `:media` queue with a concurrency limit of 5 only on the local node.

      Oban.start_queue(queue: :media, limit: 5, local_only: true)
      :ok

  Start the `:media` queue on a particular node.

      Oban.start_queue(queue: :media, limit: 5, node: "worker.1")
      :ok

  Start the `:media` queue in a `paused` state.

      Oban.start_queue(queue: :media, limit: 5, paused: true)
      :ok
  """
  @doc since: "0.12.0"
  @spec start_queue(name(), opts :: Keyword.t()) :: :ok | {:error, Exception.t()}
  def start_queue(name \\ __MODULE__, [_ | _] = opts) do
    conf = config(name)

    validate_queue_opts!(opts, [:queue, :local_only])
    validate_engine_meta!(conf, opts)

    data =
      opts
      |> Map.new()
      |> Map.put(:action, :start)
      |> Map.put(:ident, scope_signal(conf, opts))

    Notifier.notify(conf, :signal, data)
  end

  @doc """
  Pause a running queue, preventing it from executing any new jobs. All running jobs will remain
  running until they are finished.

  When shutdown begins all queues are paused.

  ## Options

  * `:queue` - a string or atom specifying the queue to pause, required

  * `:local_only` - whether the queue will be paused only on the local node, default: `false`

  * `:node` - restrict pausing to a particular node

  Note: by default, Oban does not verify that the given queue exists unless `:local_only`
  is set to `true` as even if the queue does not exist locally, it might be running on
  another node.

  ## Example

  Pause the default queue:

      Oban.pause_queue(queue: :default)
      :ok

  Pause the default queue, but only on the local node:

      Oban.pause_queue(queue: :default, local_only: true)
      :ok

  Pause the default queue only on a particular node:

      Oban.pause_queue(queue: :default, node: "worker.1")
      :ok
  """
  @doc since: "0.2.0"
  @spec pause_queue(name(), opts :: [queue_option()]) :: :ok | {:error, Exception.t()}
  def pause_queue(name \\ __MODULE__, [_ | _] = opts) do
    validate_queue_opts!(opts, [:queue, :local_only, :node])
    validate_queue_exists!(name, opts)

    conf = config(name)
    data = %{action: :pause, queue: opts[:queue], ident: scope_signal(conf, opts)}

    Notifier.notify(conf, :signal, data)
  end

  @doc """
  Pause all running queues to prevent them from executing any new jobs.

  See `pause_queue/2` for options and details.

  ## Example

  Pause all queues:

      Oban.pause_all_queues()

  Pause all queues on the local node:

      Oban.pause_all_queues(local_only: true)

  Pause all queues on a specific node:

      Oban.pause_all_queues(node: "worker.1")

  Pause all queues for an alternative instance name:

      Oban.pause_all_queues(MyOban)
  """
  @doc since: "2.17.0"
  @spec pause_all_queues(name(), opts :: [queue_all_option()]) :: :ok | {:error, Exception.t()}
  def pause_all_queues(name, opts) do
    pause_queue(name, Keyword.put(opts, :queue, :*))
  end

  @doc false
  def pause_all_queues(name \\ Oban)
  def pause_all_queues(opts) when is_list(opts), do: pause_all_queues(__MODULE__, opts)
  def pause_all_queues(name), do: pause_all_queues(name, [])

  @doc """
  Resume executing jobs in a paused queue.

  ## Options

  * `:queue` - a string or atom specifying the queue to resume, required

  * `:local_only` - whether the queue will be resumed only on the local node, default: `false`

  * `:node` - restrict resuming to a particular node

  Note: by default, Oban does not verify that the given queue exists unless `:local_only`
  is set to `true` as even if the queue does not exist locally, it might be running on
  another node.

  ## Example

  Resume a paused default queue:

      Oban.resume_queue(queue: :default)

  Resume the default queue, but only on the local node:

      Oban.resume_queue(queue: :default, local_only: true)

  Resume the default queue only on a particular node:

      Oban.resume_queue(queue: :default, node: "worker.1")
  """
  @doc since: "0.2.0"
  @spec resume_queue(name(), opts :: [queue_option()]) :: :ok | {:error, Exception.t()}
  def resume_queue(name \\ __MODULE__, [_ | _] = opts) do
    validate_queue_opts!(opts, [:queue, :local_only, :node])
    validate_queue_exists!(name, opts)

    conf = config(name)
    data = %{action: :resume, queue: opts[:queue], ident: scope_signal(conf, opts)}

    Notifier.notify(conf, :signal, data)
  end

  @doc """
  Resume executing jobs in all paused queues.

  See `resume_queue/2` for options and details.

  ## Example

  Resume all queues:

      Oban.resume_all_queues()

  Resume all queues on the local node:

      Oban.resume_all_queues(local_only: true)

  Resume all queues on a specific node:

      Oban.resume_all_queues(node: "worker.1")

  Resume all queues for an alternative instance name:

      Oban.resume_all_queues(MyOban)
  """
  @doc since: "2.17.0"
  @spec resume_all_queues(name(), opts :: [queue_all_option()]) :: :ok | {:error, Exception.t()}
  def resume_all_queues(name, opts) do
    resume_queue(name, Keyword.put(opts, :queue, :*))
  end

  @doc false
  def resume_all_queues(name \\ Oban)
  def resume_all_queues(opts) when is_list(opts), do: resume_all_queues(__MODULE__, opts)
  def resume_all_queues(name), do: resume_all_queues(name, [])

  @doc """
  Scale the concurrency for a queue.

  ## Options

  * `:queue` - a string or atom specifying the queue to scale, required

  * `:limit` — the new concurrency limit, required

  * `:local_only` — whether the queue will be scaled only on the local node, default: `false`

  * `:node` - restrict scaling to a particular node

  In addition, all engine-specific queue options are passed along after validation.

  Note: by default, Oban does not verify that the given queue exists unless `:local_only`
  is set to `true` as even if the queue does not exist locally, it might be running on
  another node.

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

  Scale the queue on a particular node:

      Oban.scale_queue(queue: :default, limit: 10, node: "worker.1")
      :ok
  """
  @doc since: "0.2.0"
  @spec scale_queue(name(), opts :: [queue_option() | {:limit, pos_integer()}]) ::
          :ok | {:error, Exception.t()}
  def scale_queue(name \\ __MODULE__, [_ | _] = opts) do
    conf = config(name)

    validate_queue_opts!(opts, [:queue, :local_only, :node])
    validate_engine_meta!(conf, opts)
    validate_queue_exists!(name, opts)

    data =
      opts
      |> Map.new()
      |> Map.put(:action, :scale)
      |> Map.put(:ident, scope_signal(conf, opts))

    Notifier.notify(conf, :signal, data)
  end

  @doc """
  Shutdown a queue's supervision tree and stop running jobs for that queue.

  By default this action will occur across all the running nodes. Still, if you prefer to stop the
  queue's supervision tree and stop running jobs for that queue only on the local node, you can
  pass the option: `local_only: true`

  The shutdown process pauses the queue first and allows current jobs to exit gracefully, provided
  they finish within the shutdown limit.

  Note: by default, Oban does not verify that the given queue exists unless `:local_only`
  is set to `true` as even if the queue does not exist locally, it might be running on
  another node.

  ## Options

  * `:queue` - a string or atom specifying the queue to stop, required

  * `:local_only` - whether the queue will be stopped only on the local node, default: `false`

  * `:node` - restrict stopping to a particular node

  ## Example

  Stop a running queue on all nodes:

      Oban.stop_queue(queue: :default)
      :ok

  Stop the queue only on the local node:

      Oban.stop_queue(queue: :media, local_only: true)
      :ok

  Stop the queue only on a particular node:

      Oban.stop_queue(queue: :media, node: "worker.1")
      :ok
  """
  @doc since: "0.12.0"
  @spec stop_queue(name(), opts :: [queue_option()]) :: :ok | {:error, Exception.t()}
  def stop_queue(name \\ __MODULE__, [_ | _] = opts) do
    validate_queue_opts!(opts, [:queue, :local_only, :node])
    validate_queue_exists!(name, opts)

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
        paused: false,
        queue: "default",
        running: [100, 102],
        started_at: ~D[2020-10-07 15:31:00],
        updated_at: ~D[2020-10-07 15:31:00]
      }
  """
  @doc since: "2.2.0"
  @spec check_queue(name(), opts :: [{:queue, queue_name()}]) :: queue_state()
  def check_queue(name \\ __MODULE__, [_ | _] = opts) do
    validate_queue_opts!(opts, [:queue])
    validate_queue_exists!(name, opts)

    name
    |> Registry.via({:producer, to_string(opts[:queue])})
    |> Producer.check()
  end

  @doc """
  Sets a job as `available`, adding attempts if already maxed out. Jobs currently `available`,
  `executing` or `scheduled` are ignored. The job is scheduled for immediate execution.

  ## Example

  Retry a job:

      Oban.retry_job(job)
      :ok
  """
  @doc since: "2.2.0"
  @spec retry_job(name(), job_or_id :: Job.t() | integer()) :: :ok
  def retry_job(name \\ __MODULE__, job_or_id) do
    conf = config(name)

    if is_integer(job_or_id) do
      Engine.retry_job(conf, %Job{id: job_or_id})
    else
      Engine.retry_job(conf, job_or_id)
    end
  end

  @doc """
  Retries all jobs that match on the given queryable.

  If no queryable is given, Oban will retry all jobs that aren't currently `available` or
  `executing`. Note that regardless of constraints, it will never retry `available` or
  `executing` jobs.

  ## Example

  Retries jobs in _any state_ other than `available` or `executing`:

      Oban.retry_all_jobs(Oban.Job)
      {:ok, 9}

  Retries jobs with the `retryable` state:

      Oban.Job
      |> Ecto.Query.where(state: "retryable")
      |> Oban.retry_all_jobs()
      {:ok, 3}

  Retries all inactive jobs with priority 0

      Oban.Job
      |> Ecto.Query.where(priority: 0)
      |> Oban.retry_all_jobs()
      {:ok, 5}
  """
  @doc since: "2.9.0"
  @spec retry_all_jobs(name(), queryable :: Ecto.Queryable.t()) :: {:ok, non_neg_integer()}
  def retry_all_jobs(name \\ __MODULE__, queryable) do
    conf = config(name)

    {:ok, jobs} = Engine.retry_all_jobs(conf, queryable)

    {:ok, length(jobs)}
  end

  @doc """
  Cancel an `executing`, `available`, `scheduled` or `retryable` job and mark it as `cancelled` to
  prevent it from running. If the job is currently `executing` it will be killed and otherwise it
  is ignored.

  If an executing job happens to fail before it can be cancelled the state is set to `cancelled`.
  However, if it manages to complete successfully then the state will still be `completed`.

  ## Example

  Cancel a job:

      Oban.cancel_job(job)
      :ok
  """
  @doc since: "1.3.0"
  @spec cancel_job(name(), job_or_id :: Job.t() | integer()) :: :ok
  def cancel_job(name \\ __MODULE__, job_or_id)

  def cancel_job(name, %Job{id: job_id}), do: cancel_job(name, job_id)

  def cancel_job(name, job_id) when is_integer(job_id) do
    import Ecto.Query, only: [where: 2]

    with {:ok, _count} <- cancel_all_jobs(name, where(Job, id: ^job_id)), do: :ok
  end

  @doc """
  Cancel many jobs based on a queryable and mark them as `cancelled` to prevent them from running.
  Any currently `executing` jobs are killed while the others are ignored.

  If executing jobs happen to fail before cancellation then the state is set to `cancelled`.
  However, any that complete successfully will remain `completed`.

  Only jobs with the statuses `executing`, `available`, `scheduled`, or `retryable` can be cancelled.

  ## Example

  Cancel all jobs:

      Oban.cancel_all_jobs(Oban.Job)
      {:ok, 9}

  Cancel all jobs for a specific worker:

      Oban.Job
      |> Ecto.Query.where(worker: "MyApp.MyWorker")
      |> Oban.cancel_all_jobs()
      {:ok, 2}
  """
  @doc since: "2.9.0"
  @spec cancel_all_jobs(name(), queryable :: Ecto.Queryable.t()) :: {:ok, non_neg_integer()}
  def cancel_all_jobs(name \\ __MODULE__, queryable) do
    conf = config(name)

    {:ok, cancelled_jobs} = Engine.cancel_all_jobs(conf, queryable)

    payload =
      for %{id: id, state: "executing"} <- cancelled_jobs do
        %{action: :pkill, job_id: id}
      end

    Notifier.notify(conf, :signal, payload)

    {:ok, length(cancelled_jobs)}
  end

  ## Child Spec Helpers

  defp plugin_child_spec({module, opts}, conf) do
    name = Registry.via(conf.name, {:plugin, module})
    opts = Keyword.merge(opts, conf: conf, name: name)

    Supervisor.child_spec({module, opts}, id: {:plugin, module})
  end

  defp event_child_spec(conf) do
    time = %{system_time: System.system_time()}
    meta = %{pid: self(), conf: conf}

    [Task.child_spec(fn -> :telemetry.execute([:oban, :supervisor, :init], time, meta) end)]
  end

  ## Signal Helper

  defp scope_signal(conf, opts) do
    cond do
      Keyword.get(opts, :local_only) ->
        Config.to_ident(conf)

      Keyword.has_key?(opts, :node) ->
        Config.to_ident(%{conf | node: opts[:node]})

      true ->
        :any
    end
  end

  ## Validation Helpers

  defp validate_queue_opts!(opts, expected) when is_list(opts) do
    unless Keyword.has_key?(opts, :queue) do
      raise ArgumentError, "required option :queue is missing from #{inspect(opts)}"
    end

    opts
    |> Keyword.take(expected)
    |> Enum.each(&validate_queue_opts!/1)
  end

  defp validate_queue_opts!({:queue, queue}) do
    unless (is_atom(queue) and not is_nil(queue)) or (is_binary(queue) and byte_size(queue) > 0) do
      raise ArgumentError,
            "expected :queue to be a binary or atom (except `nil`), got: #{inspect(queue)}"
    end
  end

  defp validate_queue_opts!({:local_only, local_only}) do
    unless is_boolean(local_only) do
      raise ArgumentError, "expected :local_only to be a boolean, got: #{inspect(local_only)}"
    end
  end

  defp validate_queue_opts!({:node, node}) do
    unless (is_atom(node) and not is_nil(node)) or (is_binary(node) and byte_size(node) > 0) do
      raise ArgumentError,
            "expected :node to be a binary or atom (except `nil`), got: #{inspect(node)}"
    end
  end

  defp validate_queue_opts!(option) do
    raise ArgumentError, "unknown option provided #{inspect(option)}"
  end

  defp validate_engine_meta!(conf, opts) do
    opts =
      opts
      |> Keyword.drop([:local_only])
      |> Keyword.put(:validate, true)

    with {:error, error} <- conf.engine.init(conf, opts), do: raise(error)
  end

  defp validate_queue_exists!(name, opts) do
    queue = Keyword.fetch!(opts, :queue)
    lonly = Keyword.get(opts, :local_only, false)

    cond do
      queue == :* ->
        :ok

      lonly and is_nil(Registry.whereis(name, {:producer, to_string(queue)})) ->
        raise ArgumentError, "queue #{inspect(queue)} does not exist locally"

      true ->
        :ok
    end
  end
end
