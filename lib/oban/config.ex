defmodule Oban.Config do
  @moduledoc false

  # main (the module that "used" oban) -- used for the consumer group name
  # node (node, dyno or hostname) -- should be static, this is the consumer

  @type t :: %__MODULE__{
    config_name: GenServer.name(),
    database: module(),
    database_name: GenServer.name(),
    database_opts: Keyword.t(),
    main: module(),
    node: binary(),
    queues: [{atom(), pos_integer()}]
  }

  @enforce_keys [:main, :node]
  defstruct config_name: Oban.Config,
            database: Oban.Database.Memory,
            database_name: Oban.Database,
            database_opts: [],
            main: nil,
            node: nil,
            queues: [default: 10]

  @doc false
  @spec child_spec(t()) :: Supervisor.child_spec()
  def child_spec(config) do
    %{id: __MODULE__, start: {Agent, :start_link, [fn -> config end]}}
  end

  @doc """
  Instantiate a new config struct with auto-generated fields provided and types validated.

  When the `node` value hasn't been configured it will be generated based on the environment.

    - In a distributed system then the node name is used
    - In the Heroku environment the system environment's `DYNO` value is used
    - Otherwise the node name is the system hostname
  """
  @spec new(Keyword.t()) :: t()
  def new(opts) when is_list(opts) do
    opts = Keyword.put_new(opts, :node, node_name())

    struct!(__MODULE__, opts)
  end

  @doc """
  Get the configuration for a given pid.

  Each oban supervision tree stores a configuration instance.
  """
  @spec get(server :: pid()) :: t()
  def get(server) when is_pid(server) do
    Agent.get(server, &(&1))
  end

  @doc false
  def node_name(env \\ System.get_env()) do
    cond do
      Node.alive?() ->
        to_string(node())

      Map.has_key?(env, "DYNO") ->
        Map.get(env, "DYNO")

      true ->
        :inet.gethostname()
        |> elem(1)
        |> to_string()
    end
  end
end
