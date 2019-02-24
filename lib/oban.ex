defmodule Oban do
  @moduledoc false

  use Supervisor

  alias Oban.Config
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
    children = Enum.map(queues, &queue_spec(&1, conf))

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp queue_spec({queue, limit}, conf) do
    queue = to_string(queue)
    name = Module.concat([conf.name, "Queue", String.capitalize(queue)])
    opts = [conf: conf, queue: queue, limit: limit, name: name]

    Supervisor.child_spec({QueueSupervisor, opts}, id: name)
  end
end
