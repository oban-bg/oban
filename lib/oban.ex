defmodule Oban do
  @moduledoc """
  This is a stub. New documentation will be added below, but this module isn't properly
  documented.

  ## Error Handling

  When a job raises an error or exits during execution the details are recorded within the
  `errors` array on the job. Provided the number of execution attempts is below the configured
  `max_attempts`, the job will automatically be retried in the future. The retry delay has a
  quadratic backoff, meaning the job's second attempt will be after 16s, third after 31s, fourth
  after 1m 36s, etc.

  #### Error Details

  Execution errors are stored as a formatted exception along with metadata about when the failure
  ocurred and which attempt caused it. Each error is stored with the following keys:

  - `at` The utc timestamp when the error occurred at
  - `attempt` The attempt number when the error ocurred
  - `error` A formatted error message and stacktrace

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
  """

  use Supervisor

  alias Oban.{Config, Notifier, Pruner}
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
  * `:poll_interval` - the amount of time between a queue pulling new jobs, specified in
    milliseconds. This is directly tied to the resolution of scheduled jobs. For example, with a
    `poll_interval` of 5_000ms scheduled jobs would be checked every 5 seconds. The default is
    `1_000`, or 1 second.
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
    conf = Config.new(opts)

    Supervisor.start_link(__MODULE__, conf, name: conf.name)
  end

  @impl Supervisor
  def init(%Config{queues: queues} = conf) do
    children = [prune_spec(conf), notifier_spec(conf)]
    children = children ++ Enum.map(queues, &queue_spec(&1, conf))

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Pause a running queue, preventing it from executing any new jobs. All running jobs will remain
  running until they are finished.

  When shutdown begins all queues are paused.

  ## Example

  Pause the default queue:

      Oban.pause_queue(:default)
      :ok

  Pause a queue with a custom named Oban supervisor:

      Oban.pause_queue(MyOban, :priority)
      :ok
  """
  @spec pause_queue(name :: module(), queue :: atom()) :: :ok
  def pause_queue(name \\ __MODULE__, queue) when is_atom(name) and is_atom(queue) do
    name
    |> Module.concat("Notifier")
    |> Notifier.pause_queue(queue)
  end

  @doc """
  Resume executing jobs in a paused queue.

  ## Example

  Resume a paused default queue:

      Oban.resume_queue(:default)
      :ok

  Resume a paused queue with custom named Oban supervisor:

      Oban.resume_queue(MyOban, :priority)
      :ok
  """
  @spec resume_queue(name :: module(), queue :: atom()) :: :ok
  def resume_queue(name \\ __MODULE__, queue) when is_atom(name) and is_atom(queue) do
    name
    |> Module.concat("Notifier")
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
  @spec scale_queue(name :: module(), queue :: atom(), scale :: pos_integer()) :: :ok
  def scale_queue(name \\ __MODULE__, queue, scale)
      when is_atom(queue) and is_integer(scale) and scale > 0 do
    name
    |> Module.concat("Notifier")
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
  @spec kill_job(name :: module(), job_id :: pos_integer()) :: :ok
  def kill_job(name \\ __MODULE__, job_id) when is_integer(job_id) do
    name
    |> Module.concat("Notifier")
    |> Notifier.kill_job(job_id)
  end

  defp prune_spec(conf) do
    name = Module.concat([conf.name, "Pruner"])
    opts = [conf: conf, name: name]

    Supervisor.child_spec({Pruner, opts}, id: name)
  end

  defp notifier_spec(conf) do
    name = Module.concat([conf.name, "Notifier"])
    opts = [conf: conf, name: name]

    Supervisor.child_spec({Notifier, opts}, id: name)
  end

  defp queue_spec({queue, limit}, conf) do
    queue = to_string(queue)
    name = Module.concat([conf.name, "Queue", String.capitalize(queue)])
    opts = [conf: conf, queue: queue, limit: limit, name: name]

    Supervisor.child_spec({QueueSupervisor, opts}, id: name)
  end
end
