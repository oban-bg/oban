defmodule Oban do
  @moduledoc """
  This is a stub. New documentation will be added below, but this module isn't properly
  documented.

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

  alias Oban.{Config, Pruner}
  alias Oban.Queue.Supervisor, as: QueueSupervisor

  @type supervisor_option ::
          {:name, module()}
          | {:node, binary()}
          | {:queues, [{atom(), pos_integer()}]}
          | {:repo, module()}

  @doc """
  Starts an `Oban` supervision tree linked to the current process.

  ## Options

  * `:name` — used for name supervisor registration
  * `:node` — used to identify the node that the supervision tree is running in. If no value is
    provided it will use the `node` name in a distributed system, the `hostname` in an isolated
    node. See the "Node Name"
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
  @spec start_link([supervisor_option()]) :: Supervisor.on_start()
  def start_link(opts) when is_list(opts) do
    conf = Config.new(opts)

    Supervisor.start_link(__MODULE__, conf, name: conf.name)
  end

  @impl Supervisor
  def init(%Config{queues: queues} = conf) do
    children = [prune_spec(conf) | Enum.map(queues, &queue_spec(&1, conf))]

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp prune_spec(conf) do
    name = Module.concat([conf.name, "Pruner"])

    {Pruner, conf: conf, name: name}
  end

  defp queue_spec({queue, limit}, conf) do
    queue = to_string(queue)
    name = Module.concat([conf.name, "Queue", String.capitalize(queue)])
    opts = [conf: conf, queue: queue, limit: limit, name: name]

    Supervisor.child_spec({QueueSupervisor, opts}, id: name)
  end
end
