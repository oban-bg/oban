defmodule Oban do
  @moduledoc """
  Oban isn't an application and won't be started automatically. It is started by a supervisor that
  must be included in your application's supervision tree. All of your configuration is passed
  into the `Oban` supervisor, allowing you to configure Oban like the rest of your application.

  ```elixir
  # confg/config.exs
  config :my_app, Oban,
    repo: MyApp.Repo,
    queues: [default: 10, events: 50, media: 20]

  # lib/my_app/application.ex
  defmodule MyApp.Application do
    @moduledoc false

    use Application

    alias MyApp.{Endpoint, Repo}

    def start(_type, _args) do
      children = [
        Repo,
        Endpoint,
        {Oban, Application.get_env(:my_app, Oban)}
      ]

      Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)
    end
  end
  ```

  ## Configuring Queues

  Queues are specified as a keyword list where the key is the name of the queue and the value is
  the maximum number of concurrent jobs. The following configuration would start four queues with
  concurrency ranging from 5 to 50:

  ```elixir
  queues: [default: 10, mailers: 20, events: 50, media: 5]
  ```

  There isn't a limit to the number of queues or how many jobs may execute concurrently.

  ### Caveats & Guidelines

  * Each queue will run as many jobs as possible concurrently, up to the configured limit. Make
    sure your system has enough resources (i.e. database connections) to handle the concurrent
    load.

  * Queue limits are local (per-node), not global (per-cluster). For example, running a queue with
    a local limit of one on three separate nodes is effectively a global limit of three. If you
    require a global limit you must restrict the number of nodes running a particular queue.

  * Only jobs in the configured queues will execute. Jobs in any other queue will stay in the
    database untouched.

  * Be careful how many concurrent jobs make expensive system calls (i.e. FFMpeg, ImageMagick).
    The BEAM ensures that the system stays responsive under load, but those guarantees don't apply
    when using ports or shelling out commands.

  ## Defining Workers

  Worker modules do the work of processing a job. At a minimum they must define a `perform/2`
  function, which is called first with the full `Oban.Job` struct, and subsequently with the
  `args` map if no clause matches.

  Define a worker to process jobs in the `events` queue:

  ```elixir
  defmodule MyApp.Business do
    use Oban.Worker, queue: "events", max_attempts: 10

    @impl Worker
    def perform(%{"id" => id}, _job) do
      model = MyApp.Repo.get(MyApp.Business.Man, id)

      IO.inspect(model)
    end
  end
  ```

  The value returned from `perform/2` is ignored, unless it an `{:error, reason}` tuple. With an
  error return or when perform has an uncaught exception or throw then the error is reported and
  the job is retried (provided there are attempts remaining).

  See `Oban.Worker` for more details on failure conditions and `Oban.Telemetry` for details on job
  reporting.

  ## Enqueueing Jobs

  Jobs are simply Ecto structs and are enqueued by inserting them into the database. For
  convenience and consistency all workers provide a `new/2` function that converts an args map
  into a job changeset suitable for insertion:

  ```elixir
  %{in_the: "business", of_doing: "business"}
  |> MyApp.Business.new()
  |> Oban.insert()
  ```

  The worker's defaults may be overridden by passing options:

  ```elixir
  %{vote_for: "none of the above"}
  |> MyApp.Business.new(queue: "special", max_attempts: 5)
  |> Oban.insert()
  ```

  Jobs may be scheduled at a specific datetime in the future:

  ```elixir
  %{id: 1}
  |> MyApp.Business.new(scheduled_at: ~U[2020-12-25 19:00:56.0Z])
  |> Oban.insert()
  ```

  Jobs may also be scheduled down to the second any time in the future:

  ```elixir
  %{id: 1}
  |> MyApp.Business.new(schedule_in: 5)
  |> Oban.insert()
  ```

  Unique jobs can be configured in the worker, or when the job is built:

  ```elixir
  %{email: "brewster@example.com"}
  |> MyApp.Mailer.new(unique: [period: 300, fields: [:queue, :worker])
  |> Oban.insert()
  ```

  Multiple jobs can be inserted in a single transaction:

  ```elixir
  Ecto.Multi.new()
  |> Oban.insert(:b_job, MyApp.Business.new(%{id: 1}))
  |> Oban.insert(:m_job, MyApp.Mailer.new(%{email: "brewser@example.com"}))
  |> Repo.transaction()
  ```

  Occasionally you may need to insert a job for a worker that exists in another
  application. In that case you can use `Oban.Job.new/2` to build the changeset
  manually:

  ```elixir
  %{id: 1, user_id: 2}
  |> Oban.Job.new(queue: :default, worker: OtherApp.Worker)
  |> Oban.insert()
  ```

  `Oban.insert/2,4` is the preferred way of inserting jobs as it provides some of
  Oban's advanced features (i.e., unique jobs). However, you can use your
  application's `Repo.insert/2` function if necessary.

  See `Oban.Job.new/2` for a full list of job options.

  ## Unique Jobs

  The unique jobs feature lets you specify constraints to prevent enqueuing duplicate jobs.
  Uniquness is based on a combination of `args`, `queue`, `worker`, `state` and insertion time. It
  is configured at the worker or job level using the following options:

  * `:period` — The number of seconds until a job is no longer considered duplicate. You should
    always specify a period.

  * `:fields` — The fields to compare when evaluating uniqueness. The available fields are
    `:args`, `:queue` and `:worker`, by default all three are used.

  * `:states` — The job states that are checked for duplicates. The available states are
    `:available`, `:scheduled`, `:executing`, `:retryable` and `:completed`. By default all states
    are checked, which prevents _any_ duplicates, even if the previous job has been completed.

  For example, configure a worker to be unique across all fields and states for 60 seconds:

  ```elixir
  use Oban.Worker, unique: [period: 60]
  ```

  Configure the worker to be unique only by `:worker` and `:queue`:

  ```elixir
  use Oban.Worker, unique: [fields: [:queue, :worker], period: 60]
  ```

  Or, configure a worker to be unique until it has executed:

  ```elixir
  use Oban.Worker, unique: [period: 300, states: [:available, :scheduled, :executing]]
  ```

  ### Stronger Guarantees

  Oban's unique job support is built on a client side read/write cycle. That makes it subject to
  duplicate writes if two transactions are started simultaneously. If you _absolutely must_ ensure
  that a duplicate job isn't inserted then you will have to make use of unique constraints within
  the database. `Oban.insert/2,4` will handle unique constraints safely through upsert support.

  ### Performance Note

  If your application makes heavy use of unique jobs you may want to add indexes on the `args` and
  `inserted_at` columns of the `oban_jobs` table. The other columns considered for uniqueness are
  already covered by indexes.

  ## Periodic (CRON) Jobs

  Oban allows jobs to be registered with a cron-like schedule and enqueued automatically. Periodic
  jobs are registered as a list of `{cron, worker}` or `{cron, worker, options}` tuples:

  ```elixir
  config :my_app, Oban, repo: MyApp.Repo, crontab: [
    {"* * * * *", MyApp.MinuteWorker},
    {"0 * * * *", MyApp.HourlyWorker, args: %{custom: "arg"}},
    {"0 0 * * *", MyApp.DailyWorker, max_attempts: 1},
    {"0 12 * * MON", MyApp.MondayWorker, queue: "scheduled"}
  ]
  ```

  These jobs would be executed as follows:

    * `MyApp.MinuteWorker` - Executed once every minute
    * `MyApp.HourlyWorker` - Executed at the first minute of every hour with custom args
    * `MyApp.DailyWorker` - Executed at midnight every day with no retries
    * `MyApp.MondayWorker` — Executed at noon every Monday in the "scheduled" queue

  The crontab format respects all [standard rules][cron] and has one minute resolution. Jobs are
  considered unique for most of each minute, which prevents duplicate jobs with multiple nodes and
  across node restarts.

  ### Cron Expressions

  Standard Cron expressions are composed of rules specifying the minutes, hours, days, months and
  weekdays. Rules for each field are comprised of literal values, wildcards, step values or
  ranges:

  * `*` - Wildcard, matches any value (0, 1, 2, ...)
  * `0` — Literal, matches only itself (only 0)
  * `*/15` — Step, matches any value that is a multiple (0, 15, 30, 45)
  * `0-5` — Range, matches any value within the range (0, 1, 2, 3, 4, 5)

  Each part may have multiple rules, where rules are separated by a comma. The allowed values for
  each field are as follows:

  * `minute` - 0-59
  * `hour` - 0-23
  * `days` - 1-31
  * `month` - 1-12 (or aliases, `JAN`, `FEB`, `MAR`, etc.)
  * `weekdays` - 0-6 (or aliases, `SUN`, `MON`, `TUE`, etc.)

  Some specific examples that demonstrate the full range of expressions:

  * `0 * * * *` — The first minute of every hour
  * `*/15 9-17 * * *` — Every fifteen minutes during standard business hours
  * `0 0 * DEC *` — Once a day at midnight during december
  * `0 7-9,4-6 13 * FRI` — Once an hour during both rush hours on Friday the 13th

  For more in depth information see the man documentation for `cron` and `crontab` in your system.
  Alternatively you can experiment with various expressions online at [Crontab Guru][guru].

  ### Caveats

  * All schedules are evaluated as UTC, the local timezone is never taken into account.

  * Workers can be used for regular and scheduled jobs so long as they accept different arguments.

  * Duplicate jobs are prevented through transactional locks and unique constraints. Workers that
    are used for regular and scheduled jobs _must not_ specify `unique` options less than `60s`.

  * Long running jobs may execute simultaneously if the scheduling interval is shorter than it
    takes to execute the job. You can prevent overlap by passing custom `unique` opts in the crontab
    config:

    ```elixir
    custom_args = %{scheduled: true}

    unique_opts = [
      period: 60 * 60 * 24,
      states: [:available, :scheduled, :executing]
    ]

    config :my_app, Oban, repo: MyApp.Repo, crontab: [
      {"* * * * *", MyApp.SlowWorker, args: custom_args, unique: unique_opts},
    ]
    ```

  [cron]: https://en.wikipedia.org/wiki/Cron#Overview
  [guru]: https://crontab.guru

  ## Testing

  As noted in the Usage section above there are some guidelines for running tests:

  * Disable all job dispatching by setting `queues: false` or `queues: nil` in your `test.exs`
    config. Keyword configuration is deep merged, so setting `queues: []` won't have any effect.

  * Disable pruning via `prune: :disabled`. Pruning isn't necessary in testing mode because jobs
    created within the sandbox are rolled back at the end of the test. Additionally, the periodic
    pruning queries will raise `DBConnection.OwnershipError` when the application boots.

  * Be sure to use the Ecto Sandbox for testing. Oban makes use of database pubsub events to
  dispatch jobs, but pubsub events never fire within a transaction.  Since sandbox tests run
  within a transaction no events will fire and jobs won't be dispatched.

    ```elixir
    config :my_app, MyApp.Repo, pool: Ecto.Adapters.SQL.Sandbox
    ```

  Oban provides some helpers to facilitate testing. The helpers handle the boilerplate of making
  assertions on which jobs are enqueued. To use the `assert_enqueued/1` and `refute_enqueued/1`
  helpers in your tests you must include them in your testing module and specify your app's Ecto
  repo:

  ```elixir
  use Oban.Testing, repo: MyApp.Repo
  ```

  Now you can assert, refute or list jobs that have been enqueued within your tests:

  ```elixir
  assert_enqueued worker: MyWorker, args: %{id: 1}

  # or

  refute_enqueued queue: "special", args: %{id: 2}

  # or

  assert [%{args: %{"id" => 1}}] = all_enqueued worker: MyWorker
  ```

  See the `Oban.Testing` module for more details on making assertions.

  ### Integration Testing

  During integration testing it may be necessary to run jobs because they do work essential for
  the test to complete, i.e. sending an email, processing media, etc. You can execute all
  available jobs in a particular queue by calling `Oban.drain_queue/3` directly from your tests.

  For example, to process all pending jobs in the "mailer" queue while testing some business
  logic:

  ```elixir
  defmodule MyApp.BusinessTest do
    use MyApp.DataCase, async: true

    alias MyApp.{Business, Worker}

    test "we stay in the business of doing business" do
      :ok = Business.schedule_a_meeting(%{email: "monty@brewster.com"})

      assert %{success: 1, failure: 0} == Oban.drain_queue(:mailer)

      # Make an assertion about the email delivery
    end
  end
  ```

  See `Oban.drain_queue/3` for additional details.

  ## Error Handling

  When a job returns an error value, raises an error or exits during execution the details are
  recorded within the `errors` array on the job. When the number of execution attempts is below
  the configured `max_attempts` limit, the job will automatically be retried in the future.

  The retry delay has an exponential backoff, meaning the job's second attempt will be after 16s,
  third after 31s, fourth after 1m 36s, etc.

  See the `Oban.Worker` documentation on "Customizing Backoff" for alternative backoff strategies.

  ### Error Details

  Execution errors are stored as a formatted exception along with metadata about when the failure
  ocurred and which attempt caused it. Each error is stored with the following keys:

  * `at` The utc timestamp when the error occurred at
  * `attempt` The attempt number when the error ocurred
  * `error` A formatted error message and stacktrace

  See the [Instrumentation](#module-instrumentation) docs below for an example of integrating with
  external error reporting systems.

  ### Limiting Retries

  By default jobs are retried up to 20 times. The number of retries is controlled by the
  `max_attempts` value, which can be set at the Worker or Job level. For example, to instruct a
  worker to discard jobs after three failures:

      use Oban.Worker, queue: "limited", max_attempts: 3

  ## Pruning Historic Jobs

  Job stats and queue introspection is built on keeping job rows in the database after they have
  completed. This allows administrators to review completed jobs and build informative aggregates,
  but at the expense of storage and an unbounded table size. To prevent the `oban_jobs` table from
  growing indefinitely, Oban provides active pruning of `completed` jobs.

  By default, pruning is disabled. To enable pruning we configure a supervision tree with the
  `:prune` option. There are three distinct modes of pruning:

    * `:disabled` - This is the default, where no pruning happens at all
    * `{:maxlen, count}` - Pruning is based on the number of rows in the table, any rows beyond
      the configured `count` are deleted
    * `{:maxage, seconds}` - Pruning is based on a row's age, any rows older than the configured
      number of `seconds` are deleted. The age unit is always specified in seconds, but values
      on the scale of days, weeks or months are perfectly acceptable.

  Pruning is best-effort and performed out-of-band. This means that all limits are soft; jobs
  beyond a specified length or age may not be pruned immediately after jobs complete. Prune timing
  is based on the configured `prune_interval`, which is one minute by default.

  Only jobs in a `completed` or `discarded` state can be deleted. Currently `executing` jobs and
  older jobs that are still in the `available` state are retained.

  ## Pulse Tracking (Heartbeats)

  Historic introspection is a defining feature of Oban. In addition to retaining completed jobs
  Oban also generates "heartbeat" records every second for each running queue.

  Heartbeat records are recorded in the `oban_beats` table and pruned to an hour of backlog. The
  recorded information is used for a couple of purposes:

  1. To track active jobs. When a job executes it records the node and queue that ran it in the
    `attempted_by` column. Zombie jobs (jobs that were left executing when a producer crashes or the
    node is shut down) are found by comparing the `attempted_by` values with recent heartbeat
    records and resurrected accordingly.
  2. Each heartbeat records information about a node/queue pair such as whether it is paused, what
    the execution limit is and exactly which jobs are running. These records can power additional
    logging or metrics (and are the backbone of the Oban UI).

  ## Instrumentation & Logging

  Oban provides integration with [Telemetry][tele], a dispatching library for metrics. It is easy
  to report Oban metrics to any backend by attaching to `:oban` events.

  For instructions on using the default structured logger and information on event metadata see
  docs for the `Oban.Telemetry` module.

  [tele]: https://hexdocs.pm/telemetry

  ## Prefix Support

  Oban supports namespacing through PostgreSQL schemas, also called "prefixes" in Ecto. With
  prefixes your jobs table can reside outside of your primary schema (usually public) and you can
  have multiple separate job tables.

  To use a prefix you first have to specify it within your migration:

  ```elixir
  defmodule MyApp.Repo.Migrations.AddPrefixedObanJobsTable do
    use Ecto.Migration

    def up do
      Oban.Migrations.up(prefix: "private")
    end

    def down do
      Oban.Migrations.down(prefix: "private")
    end
  end
  ```

  The migration will create the "private" schema and all tables, functions and triggers within
  that schema. With the database migrated you'll then specify the prefix in your configuration:

  ```elixir
  config :my_app, Oban,
    prefix: "private",
    repo: MyApp.Repo,
    queues: [default: 10]
  ```

  Now all jobs are inserted and executed using the `private.oban_jobs` table. Note that
  `Oban.insert/2,4` will write jobs in the `private.oban_jobs` table, you'll need to specify a
  prefix manually if you insert jobs directly through a repo.

  ### Isolation

  Not only is the `oban_jobs` table isolated within the schema, but all notification events are
  also isolated. That means that insert/update events will only dispatch new jobs for their
  prefix. You can run multiple Oban instances with different prefixes on the same system and have
  them entirely isolated, provided you give each supervisor a distinct id.

  Here we configure our application to start three Oban supervisors using the "public", "special"
  and "private" prefixes, respectively:

  ```elixir
  def start(_type, _args) do
    children = [
      Repo,
      Endpoint,
      Supervisor.child_spec({Oban, name: ObanA, repo: Repo}, id: ObanA),
      Supervisor.child_spec({Oban, name: ObanB, repo: Repo, prefix: "special"}, id: ObanB),
      Supervisor.child_spec({Oban, name: ObanC, repo: Repo, prefix: "private"}, id: ObanC)
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)
  end
  ```
  """
  @moduledoc since: "0.1.0"

  use Supervisor

  import Oban.Notifier, only: [signal: 0]

  alias Ecto.{Changeset, Multi}
  alias Oban.{Config, Job, Midwife, Notifier, Pruner, Query}
  alias Oban.Crontab.Scheduler
  alias Oban.Queue.Producer
  alias Oban.Queue.Supervisor, as: QueueSupervisor

  @type option ::
          {:name, module()}
          | {:node, binary()}
          | {:poll_interval, pos_integer()}
          | {:prefix, binary()}
          | {:prune, :disabled | {:maxlen, pos_integer()} | {:maxage, pos_integer()}}
          | {:prune_interval, pos_integer()}
          | {:prune_limit, pos_integer()}
          | {:queues, [{atom(), pos_integer()}]}
          | {:repo, module()}
          | {:shutdown_grace_period, timeout()}
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
  * `:prune` - configures job pruning behavior, see "Pruning Historic Jobs" for more information
  * `:queues` — a keyword list where the keys are queue names and the values are the concurrency
    setting. For example, setting queues to `[default: 10, exports: 5]` would start the queues
    `default` and `exports` with a combined concurrency level of 20. The concurrency setting
    specifies how many jobs _each queue_ will run concurrently.

    For testing purposes `:queues` may be set to `false` or `nil`, which effectively disables all
    job dispatching.
  * `:verbose` — either `false` to disable logging or a standard log level (`:error`, `:warn`,
    `:info`, `:debug`). This determines whether queries are logged or not; overriding the repo's
    configured log level. Defaults to `false`, where no queries are logged.

  ### Twiddly Options

  Additional options used to tune system behaviour. These are primarily useful for testing or
  troubleshooting and shouldn't be changed usually.

  * `:circuit_backoff` — the number of milliseconds until queries are attempted after a database
    error. All processes communicating with the database are equipped with circuit breakers and
    will use this for the backoff. Defaults to `30_000ms`.
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
          multi_name :: term(),
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
          multi_name :: term(),
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
