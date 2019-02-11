defmodule Oban do
  @moduledoc false

  alias Oban.Supervisor

  @type supervisor_option ::
    {:name, module()}
    | {:node, binary()}
    | {:queues, [{atom(), pos_integer()}]}
    | {:repo, module()}

  @doc """
  Starts an `Oban` supervision tree linked to the current process.

  ## Options

    * `:repo` — specifies the Ecto repo used to insert and retreive jobs.
    * `:name` — used for name supervisor registration
    * `:node` — used to identify the node that the supervision tree is running in. If no value is
      provided it will use the `node` name in a distributed system, the `hostname` in an
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

  @doc false
  defmacro __using__(opts) do
    quote location: :keep do
      @behaviour Oban

      @supervisor_name Module.concat(__MODULE__, "Supervisor")
      @config_name Module.concat(__MODULE__, "Config")

      @opts unquote(opts)
            |> Keyword.put(:name, @supervisor_name)
            |> Keyword.put(:config_name, @config_name)

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
    end
  end
end
