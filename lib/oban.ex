defmodule Oban do
  @moduledoc ~S"""
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

  Queues are specified as a keyword list where the key is the name of the queue
  and the value is the maximum number of concurrent jobs. The following
  configuration would start four queues with concurrency ranging from 5 to 50:

  ```elixir
  queues: [default: 10, mailers: 20, events: 50, media: 5]
  ```

  There isn't a limit to the number of queues or how many jobs may execute
  concurrently. Here are a few caveats and guidelines:

  * Each queue will run as many jobs as possible concurrently, up to the
    configured limit. Make sure your system has enough resources (i.e. database
    connections) to handle the concurrent load.
  * Only jobs in the configured queues will execute. Jobs in any other queue
    will stay in the database untouched.
  * Be careful how many concurrent jobs make expensive system calls (i.e. FFMpeg,
    ImageMagick). The BEAM ensures that the system stays responsive under load,
    but those guarantees don't apply when using ports or shelling out commands.

  ### Creating Workers

  Worker modules do the work of processing a job. At a minimum they must define a
  `perform/1` function, which is called with an `args` map.

  Define a worker to process jobs in the `events` queue:

  ```elixir
  defmodule MyApp.Workers.Business do
    use Oban.Worker, queue: "events", max_attempts: 10

    @impl Oban.Worker
    def perform(%{"id" => id}) do
      model = MyApp.Repo.get(MyApp.Business.Man, id)

      IO.inspect(model)
    end
  end
  ```

  The return value of `perform/1` doesn't matter and is entirely ignored. If the
  job raises an exception or throws an exit then the error will be reported and
  the job will be retried (provided there are attempts remaining).

  See `Oban.Worker` for more details.

  ### Enqueueing Jobs

  Jobs are simply `Ecto` structs and are enqueued by inserting them into the
  database. Here we insert a job into the `default` queue and specify the worker
  by module name:

  ```elixir
  %{id: 1, user_id: 2}
  |> Oban.Job.new(queue: :default, worker: MyApp.Worker)
  |> MyApp.Repo.insert()
  ```

  For convenience and consistency all workers implement a `new/2` function that
  converts an args map into a job changeset suitable for inserting into the
  database:

  ```elixir
  %{in_the: "business", of_doing: "business"}
  |> MyApp.Workers.Business.new()
  |> MyApp.Repo.insert()
  ```

  The worker's defaults may be overridden by passing options:

  ```elixir
  %{vote_for: "none of the above"}
  |> MyApp.Workers.Business.new(queue: "special", max_attempts: 5)
  |> MyApp.Repo.insert()
  ```

  Jobs may be scheduled down to the second any time in the future:

  ```elixir
  %{id: 1}
  |> MyApp.Workers.Business.new(schedule_in: 5)
  |> MyApp.Repo.insert()
  ```

  See `Oban.Job.new/2` for a full list of job options.

  ## Testing

  As noted in the Usage section above there are some guidelines for running tests:

  * Disable all job dispatching by setting `queues: false` or `queues: nil` in your `test.exs`
    config. Keyword configuration is deep merged, so setting `queues: []` won't have any effect.

  * Disable pruning via `prune: :disabled`. Pruning isn't necessary in testing mode because jobs
    created within the sandbox are rolled back at the end of the test. Additionally, the periodic
    pruning queries will raise `DBConnection.OwnershipError` when the application boots.

  * Be sure to use the Ecto Sandbox for testing. Oban makes use of database pubsub
    events to dispatch jobs, but pubsub events never fire within a transaction.
    Since sandbox tests run within a transaction no events will fire and jobs
    won't be dispatched.

    ```elixir
    config :my_app, MyApp.Repo, pool: Ecto.Adapters.SQL.Sandbox
    ```

  Oban provides some helpers to facilitate testing. The helpers handle the
  boilerplate of making assertions on which jobs are enqueued. To use the
  `assert_enqueued/1` and `refute_enqueued/1` helpers in your tests you must
  include them in your testing module and specify your app's Ecto repo:

  ```elixir
  use Oban.Testing, repo: MyApp.Repo
  ```

  Now you can assert or refute that jobs have been enqueued within your tests:

  ```elixir
  assert_enqueued worker: MyWorker, args: %{id: 1}

  # or

  refute_enqueued queue: "special", args: %{id: 2}
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

      assert 1 == Oban.drain_queue(:mailer)

      # Make an assertion about the email delivery
    end
  end
  ```

  See `Oban.drain_queue/1` for additional details.

  ## Error Handling

  When a job raises an error or exits during execution the details are recorded within the
  `errors` array on the job. Provided the number of execution attempts is below the configured
  `max_attempts`, the job will automatically be retried in the future. The retry delay has a
  quadratic backoff, meaning the job's second attempt will be after 16s, third after 31s, fourth
  after 1m 36s, etc.

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
  is based on the configured `poll_interval`, where pruning occurs once for every 60 queue polls.
  With the default `poll_interval` of 1 second that means pruning occurs at system startup and
  then once every minute afterwards.

  Note, only jobs in a `completed` or `discarded` state will be deleted. Currently `executing`
  jobs and older jobs that are still in the `available` state will be retained.

  ## Instrumentation

  Oban provides integration with [Telemetry][tele], a dispatching library for metrics. It is easy
  to report Oban metrics to any backend by attaching to `:oban` events.

  For exmaple, to log out the duration for all executed jobs:

  ```elixir
  defmodule ObanLogger do
    require Logger

    def handle_event([:oban, :job, :executed], %{duration: duration}, meta, _config) do
      Logger.info("[#{meta.queue}] #{meta.worker} #{meta.event} in #{duration}")
    end
  end

  :telemetry.attach("oban-logger", [:oban, :job, :executed], &ObanLogger.handle_event/4, nil)
  ```

  Another great use of execution data is error reporting. Here is an example of
  integrating with [Honeybadger][honey]:

  ```elixir
  defmodule ErrorReporter do
    def handle_event([:oban, :job, :failure], _timing, %{event: :failure} = meta, _config) do
      context = Map.take(meta, [:id, :args, :queue, :worker])

      Honeybadger.notify(meta.error, context, meta.stack)
    end
  end

  :telemetry.attach("oban-errors", [:oban, :job, :executed], &ErrorReporter.handle_event/4, nil)
  ```

  Here is a reference for metric event metadata:

  | event      | metadata                                             |
  | ---------- | ---------------------------------------------------- |
  | `:success` | `:id, :args, :queue, :worker`                        |
  | `:failure` | `:id, :args, :queue, :worker, :kind, :error, :stack` |

  [tele]: https://hexdocs.pm/telemetry
  [honey]: https://honeybadger.io
  """

  use Supervisor

  alias Oban.{Config, Notifier, Pruner}
  alias Oban.Queue.Producer
  alias Oban.Queue.Supervisor, as: QueueSupervisor

  @type option ::
          {:name, module()}
          | {:node, binary()}
          | {:poll_interval, pos_integer()}
          | {:prune, :disabled | {:maxlen, pos_integer()} | {:maxage, pos_integer()}}
          | {:queues, [{atom(), pos_integer()}]}
          | {:repo, module()}
          | {:shutdown_grace_period, timeout()}

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
  * `:poll_interval` - the amount of time between a queue pulling new jobs, specified in
    milliseconds. This is directly tied to the resolution of _scheduled_ jobs. For example, with a
    `poll_interval` of `5_000ms`, scheduled jobs are checked every 5 seconds. The default is
    `1_000ms`.
  * `:prune` - configures job pruning behavior, see "Pruning Historic Jobs" for more information
  * `:shutdown_grace_period` - the amount of time a queue will wait for executing jobs to complete
    before hard shutdown, specified in milliseconds. The default is `15_000`, or 15 seconds.

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
  @spec start_link([option()]) :: Supervisor.on_start()
  def start_link(opts) when is_list(opts) do
    conf =
      opts
      |> Keyword.put(:queues, Keyword.get(opts, :queues) || [])
      |> Config.new()

    Supervisor.start_link(__MODULE__, conf, name: conf.name)
  end

  @impl Supervisor
  def init(%Config{queues: queues} = conf) do
    children = [
      {Config, conf: conf, name: Config},
      {Pruner, conf: conf, name: Pruner},
      {Notifier, conf: conf, name: Notifier}
    ]

    children = children ++ Enum.map(queues, &queue_spec(&1, conf))

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp queue_spec({queue, limit}, conf) do
    queue = to_string(queue)
    name = Module.concat([conf.name, "Queue", String.capitalize(queue)])
    opts = [conf: conf, queue: queue, limit: limit, name: name]

    Supervisor.child_spec({QueueSupervisor, opts}, id: name)
  end

  @doc """
  Retreive the current config struct.
  """
  defdelegate config, to: Config, as: :get

  @doc """
  Synchronously execute all available jobs in a queue. All execution happens within the current
  process and it is guaranteed not to raise an error or exit.

  Draining a queue from within the current process is especially useful for testing. Jobs that are
  enqueued by a process when Ecto is in sandbox mode are only visible to that process. Calling
  `drain_queue/1` allows you to control when the jobs are executed and to wait synchronously for
  all jobs to complete.

  ## Failures & Retries

  Draining a queue uses the same execution mechanism as regular job dispatch. That means that any
  job failures or crashes will be captured and result in a retry. Failures are _not_ reported back
  to the calling process. If you expect jobs to fail, would like to track failures, or need to
  check for specific errors you can use one of these mechanisms:

  * Check for side effects from job execution
  * Use telemetry events to track success and failure
  * Check the database for jobs with errors

  ## Example

  Drain a queue with three available jobs:

      Oban.drain_queue(:default)
      3
  """
  @spec drain_queue(queue :: atom() | binary()) :: non_neg_integer()
  def drain_queue(queue) when is_atom(queue) or is_binary(queue) do
    Producer.drain(to_string(queue), config())
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
  @spec pause_queue(queue :: atom()) :: :ok
  defdelegate pause_queue(queue), to: Notifier

  @doc """
  Resume executing jobs in a paused queue.

  ## Example

  Resume a paused default queue:

      Oban.resume_queue(:default)
      :ok
  """
  @spec resume_queue(queue :: atom()) :: :ok
  defdelegate resume_queue(queue), to: Notifier

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
  @spec scale_queue(queue :: atom(), scale :: pos_integer()) :: :ok
  defdelegate scale_queue(queue, scale), to: Notifier

  @doc """
  Kill an actively executing job and mark it as `discarded`, ensuring that it won't be retried.

  If the job happens to fail before it can be killed the state is set to `discarded`. However,
  if it manages to complete successfully then the state will still be `completed`.

  ## Example

  Kill a long running job with an id of `1`:

      Oban.kill_job(1)
      :ok
  """
  @spec kill_job(job_id :: pos_integer()) :: :ok
  defdelegate kill_job(job_id), to: Notifier
end
