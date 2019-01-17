defmodule Oban do
  @moduledoc false

  # TODO: Documentation

  alias Oban.{Config, Job, Supervisor}

  @type job_option ::
    {:args, [term()]}
    | {:queue, atom() | binary()}
    | {:worker, module() | binary()}

  @type supervisor_option ::
    {:database, module()}
    | {:database_opts, Keyword.t()}
    | {:name, module()}
    | {:node, binary()}
    | {:queues, [{atom(), pos_integer()}]}

  @doc """
  Starts an `Oban` supervision tree linked to the current process.

  ## Options

    * `:database` — specifies the database adapter used for job storage. This may be an module
      that implements the `Oban.Database` behaviour.
    * `:database_opts` — a keyword list of options that will be provided for database startup. See
      documentation for the chose database adapter for available options.
    * `:name` — used for name registration
    * `:node` — used to identify the node that the supervision tree is running in. If no value is
      provided it will use the `node` name in a distributed system, or the `hostname` in an
      isolated node.
    * `:queues` — a keyword list where the keys are queue names and the values are the concurrency
      setting. For example, setting queues to `[default: 10, exports: 5]` would start the queues
      `default` and `exports` with a combined concurrency level of 20. The concurrency setting
      specifies how many jobs _each queue_ will run concurrently.

  Note that any options passed to `start_link` will override options set through the `using` macro.

  ## Examples

  To start an `Oban` supervisor within an application's supervision tree:

      def start(_type, _args) do
        children = [MyApp.Repo, MyApp.Oban]

        Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)
      end
  """
  @callback start_link([supervisor_option()]) :: Supervisor.on_start()

  @doc """
  Push a job for asynchronous execution.

  The function will return an `Oban.Job` struct with an auto-generated id.

  ## Options

    * `:args` — a list of arguments passed to the worker during execution
    * `:queue` — a named queue to push the job into. Jobs may be pushed into any queue, regardless
      of whether jobs are currently being processed for the queue.
    * `:worker` — a module to execute the job in. The module must implement the `Oban.Worker`
      behaviour.

  ## Examples

  Push a job into the `:default` queue

      MyApp.Oban.push(args: [1, 2, 3], queue: :default, worker: MyApp.Worker)

  Generate a pre-configured job for `MyApp.Worker` and push it.

      [args: [1, 2, 3]] |> MyApp.Worker.new() |> MyApp.Oban.push()
  """
  @callback push([job_option()]) :: Job.t()

  @doc false
  defmacro __using__(opts) do
    quote location: :keep do
      @behaviour Oban

      @supervisor_name Module.concat(__MODULE__, "Supervisor")
      @config_name Module.concat(__MODULE__, "Config")
      @database_name Module.concat(__MODULE__, "Database")

      @opts unquote(opts)
            |> Keyword.put(:main, __MODULE__)
            |> Keyword.put(:name, @supervisor_name)
            |> Keyword.put(:config_name, @config_name)
            |> Keyword.put(:database_name, @database_name)

      @doc false
      def child_spec(opts) do
        %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}, type: :supervisor}
      end

      @impl Oban
      def start_link(opts \\ []) do
        @opts
        |> Keyword.merge(opts)
        |> Supervisor.start_link()
      end

      @impl Oban
      def push(job_opts) when is_list(job_opts) do
        db_pid = Process.whereis(@database_name)
        cf_pid = Process.whereis(@config_name)

        %Config{database: database} = conf = Config.get(cf_pid)

        database.push(db_pid, Job.new(job_opts), conf)
      end
    end
  end
end
