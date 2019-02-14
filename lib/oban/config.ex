defmodule Oban.Config do
  @moduledoc false

  @type t :: %__MODULE__{
          config_name: GenServer.name(),
          node: binary(),
          poll_interval: pos_integer(),
          queues: [{atom(), pos_integer()}],
          repo: module(),
          shutdown_grace_period: timeout()
        }

  @enforce_keys [:node, :repo]
  defstruct [
    :node,
    :repo,
    config_name: __MODULE__,
    poll_interval: 1_000,
    queues: [default: 10],
    shutdown_grace_period: 15_000
  ]

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
