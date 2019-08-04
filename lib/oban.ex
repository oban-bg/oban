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

  ### Configuring Queues

  Queues are specified as a keyword list where the key is the name of the queue and the value is
  the maximum number of concurrent jobs. The following configuration would start four queues with
  concurrency ranging from 5 to 50:

  ```elixir
  queues: [default: 10, mailers: 20, events: 50, media: 5]
  ```

  There isn't a limit to the number of queues or how many jobs may execute
  concurrently. Here are a few caveats and guidelines:

  * Each queue will run as many jobs as possible concurrently, up to the configured limit. Make
    sure your system has enough resources (i.e. database connections) to handle the concurrent
    load.
  * Only jobs in the configured queues will execute. Jobs in any other queue will stay in the
    database untouched.
  * Be careful how many concurrent jobs make expensive system calls (i.e. FFMpeg, ImageMagick).
    The BEAM ensures that the system stays responsive under load, but those guarantees don't apply
    when using ports or shelling out commands.

  ### Defining Workers

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
  error return or when perform has an uncaught exception or throw then the error will be reported
  and the job will be retried (provided there are attempts remaining).

  See `Oban.Worker` for more details on failure conditions and `Oban.Telemetry` for details on job
  reporting.

  ### Enqueueing Jobs

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
  * `:states` — The job states that will be checked for duplicates. The available states are
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

  ## Integration Testing

  During integration testing it may be necessary to run jobs because they do work essential for
  the test to complete, i.e. sending an email, processing media, etc. You can execute all
  available jobs in a particular queue by calling `Oban.drain_queue/1` directly from your tests.

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

  See `Oban.drain_queue/1` for additional details.

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

  By default jobs will be retried up to 20 times. The number of retries is controlled by the
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
      the configured `count` will be deleted
    * `{:maxage, seconds}` - Pruning is based on a row's age, any rows older than the configured
      number of `seconds` will be deleted. The age unit is always specified in seconds, but values
      on the scale of days, weeks or months are perfectly acceptable.

  Pruning is best-effort and performed out-of-band. This means that all limits are soft; jobs
  beyond a specified length or age may not be pruned immediately after jobs complete. Prune timing
  is based on the configured `prune_interval`, which is one minute by default.

  Only jobs in a `completed` or `discarded` state will be deleted. Currently `executing` jobs and
  older jobs that are still in the `available` state will be retained.

  ## Instrumentation & Logging

  Oban provides integration with [Telemetry][tele], a dispatching library for metrics. It is easy
  to report Oban metrics to any backend by attaching to `:oban` events.

  For instructions on using the default structured logger and information on event metadata see
  docs for the `Oban.Telemetry` module.

  [tele]: https://hexdocs.pm/telemetry
  """
  @moduledoc since: "0.1.0"

  use Supervisor

  alias Ecto.{Changeset, Multi}
  alias Oban.{Config, Job, Notifier, Pruner, Query}
  alias Oban.Queue.Producer
  alias Oban.Queue.Supervisor, as: QueueSupervisor

  @type option ::
          {:name, module()}
          | {:node, binary()}
          | {:poll_interval, pos_integer()}
          | {:prune, :disabled | {:maxlen, pos_integer()} | {:maxage, pos_integer()}}
          | {:prune_interval, pos_integer()}
          | {:prune_limit, pos_integer()}
          | {:queues, [{atom(), pos_integer()}]}
          | {:repo, module()}
          | {:shutdown_grace_period, timeout()}
          | {:verbose, boolean()}

  @doc """
  Starts an `Oban` supervision tree linked to the current process.

  ## Options

  * `:name` — used for name supervisor registration
  * `:node` — used to identify the node that the supervision tree is running in. If no value is
    provided it will use the `node` name in a distributed system, the `hostname` in an isolated
    node. See "Node Name" below.
  * `:repo` — specifies the Ecto repo used to insert and retreive jobs.
  * `:queues` — a keyword list where the keys are queue names and the values are the concurrency
    setting. For example, setting queues to `[default: 10, exports: 5]` would start the queues
    `default` and `exports` with a combined concurrency level of 20. The concurrency setting
    specifies how many jobs _each queue_ will run concurrently.

    For testing purposes `:queues` may be set to `false` or `nil`, which effectively disables all
    job dispatching.
  * `:poll_interval` - the number of milliseconds between polling for new jobs in a queue. This
    is directly tied to the resolution of _scheduled_ jobs. For example, with a `poll_interval` of
    `5_000ms`, scheduled jobs are checked every 5 seconds. The default is `1_000ms`.
  * `:prune` - configures job pruning behavior, see "Pruning Historic Jobs" for more information
  * `:prune_interval` — the number of milliseconds between calls to prune historic jobs. The
    default is `60_000ms`, or one minute.
  * `:prune_limit` – the maximum number of jobs that will be pruned at each prune interval. The
    default is `5_000`.
  * `:shutdown_grace_period` - the amount of time a queue will wait for executing jobs to complete
    before hard shutdown, specified in milliseconds. The default is `15_000`, or 15 seconds.
  * `:verbose` — determines whether queries will be logged or not, does not supersede the repo's
    configured log level. Defaults to `true`, where all queries will be logged.

  Note that any options passed to `start_link` will override options set through the `using` macro.

  ## Examples

  To start an `Oban` supervisor within an application's supervision tree:

      def start(_type, _args) do
        children = [MyApp.Repo, {Oban, queues: [default: 50]}]

        Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)
      end

  ## Node Name

  When the `node` value hasn't been configured it will be generated based on the environment:

  * In a distributed system the node name is used
  * In a Heroku environment the system environment's `DYNO` value is used
  * Otherwise, the system hostname is used
  """
  @doc since: "0.1.0"
  @spec start_link([option()]) :: Supervisor.on_start()
  def start_link(opts) when is_list(opts) do
    conf =
      opts
      |> Keyword.put(:queues, Keyword.get(opts, :queues) || [])
      |> Config.new()

    Supervisor.start_link(__MODULE__, conf, name: conf.name)
  end

  @impl Supervisor
  def init(%Config{name: name, queues: queues} = conf) do
    children = [
      {Config, conf: conf, name: child_name(name, "Config")},
      {Pruner, conf: conf, name: child_name(name, "Pruner")},
      {Notifier, conf: conf, name: child_name(name, "Notifier")}
    ]

    children = children ++ Enum.map(queues, &queue_spec(&1, conf))

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Retreive the config struct for a named Oban supervision tree.
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
  Insert a job insert operation into an `Ecto.Multi`.

  Like `insert/2`, this variant is recommended over `Ecto.Multi.insert` beause it supports all of
  Oban's features, i.e. unique jobs.

  ## Example

      Ecto.Multi.new()
      |> Oban.insert(:job_1, MyApp.Worker.new(%{id: 1}))
      |> Oban.insert(:job_2, MyApp.Worker.new(%{id: 2}))
      |> MyApp.Repo.transaction()
  """
  @doc since: "0.7.0"
  @spec insert(
          name :: atom(),
          multi :: Multi.t(),
          multi_name :: atom(),
          changeset :: Changeset.t(Job.t())
        ) :: Multi.t()
  def insert(name \\ __MODULE__, %Multi{} = multi, multi_name, %Changeset{} = changeset)
      when is_atom(name) and is_atom(multi_name) do
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
  Synchronously execute all available jobs in a queue. All execution happens within the current
  process and it is guaranteed not to raise an error or exit.

  Draining a queue from within the current process is especially useful for testing. Jobs that are
  enqueued by a process when Ecto is in sandbox mode are only visible to that process. Calling
  `drain_queue/1` allows you to control when the jobs are executed and to wait synchronously for
  all jobs to complete.

  ## Failures & Retries

  Draining a queue uses the same execution mechanism as regular job dispatch. That means that any
  job failures or crashes will be captured and result in a retry. Retries are scheduled in the
  future with backoff and won't be retried immediately.

  Exceptions are _not_ raised in to the calling process. If you expect jobs to fail, would like to
  track failures, or need to check for specific errors you can use one of these mechanisms:

  * Check for side effects from job execution
  * Use telemetry events to track success and failure
  * Check the database for jobs with errors

  ## Example

  Drain a queue with three available jobs, two of which succeed and one of which fails:

      Oban.drain_queue(:default)
      %{success: 2, failure: 1}
  """
  @doc since: "0.4.0"
  @spec drain_queue(name :: atom(), queue :: atom() | binary()) :: %{
          success: non_neg_integer(),
          failure: non_neg_integer()
        }
  def drain_queue(name \\ __MODULE__, queue)
      when is_atom(name) and (is_atom(queue) or is_binary(queue)) do
    Producer.drain(to_string(queue), config(name))
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
  @spec pause_queue(name :: atom(), queue :: atom()) :: :ok
  def pause_queue(name \\ __MODULE__, queue) when is_atom(queue) do
    name
    |> child_name("Notifier")
    |> Notifier.pause_queue(queue)
  end

  @doc """
  Resume executing jobs in a paused queue.

  ## Example

  Resume a paused default queue:

      Oban.resume_queue(:default)
      :ok
  """
  @doc since: "0.2.0"
  @spec resume_queue(name :: atom(), queue :: atom()) :: :ok
  def resume_queue(name \\ __MODULE__, queue) when is_atom(queue) do
    name
    |> child_name("Notifier")
    |> Notifier.resume_queue(queue)
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
  @spec scale_queue(name :: atom(), queue :: atom(), scale :: pos_integer()) :: :ok
  def scale_queue(name \\ __MODULE__, queue, scale)
      when is_atom(queue) and is_integer(scale) and scale > 0 do
    name
    |> child_name("Notifier")
    |> Notifier.scale_queue(queue, scale)
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
    |> child_name("Notifier")
    |> Notifier.kill_job(job_id)
  end

  defp queue_spec({queue, limit}, conf) do
    queue = to_string(queue)
    name = Module.concat([conf.name, "Queue", String.capitalize(queue)])
    opts = [conf: conf, queue: queue, limit: limit, name: name]

    Supervisor.child_spec({QueueSupervisor, opts}, id: name)
  end

  defp child_name(name, child), do: Module.concat(name, child)
end
