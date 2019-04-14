defmodule Oban.Config do
  @moduledoc false

  use Agent

  @type prune :: :disabled | {:maxlen, pos_integer()} | {:maxage, pos_integer()}

  @type t :: %__MODULE__{
          name: module(),
          node: binary(),
          poll_interval: pos_integer(),
          prune: prune(),
          queues: [{atom(), pos_integer()}],
          repo: module(),
          shutdown_grace_period: timeout()
        }

  @type option :: {:name, module()} | {:conf, t()}

  @enforce_keys [:node, :repo]
  defstruct name: Oban,
            node: nil,
            poll_interval: :timer.seconds(1),
            prune: :disabled,
            queues: [default: 10],
            repo: nil,
            shutdown_grace_period: 15_000

  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    {conf, opts} = Keyword.pop(opts, :conf)

    Agent.start_link(fn -> conf end, opts)
  end

  @spec new(Keyword.t()) :: t()
  def new(opts) when is_list(opts) do
    opts = Keyword.put_new(opts, :node, node_name())

    struct!(__MODULE__, opts)
  end

  @spec get() :: t()
  def get(name \\ __MODULE__), do: Agent.get(name, & &1)

  @spec node_name(%{optional(binary()) => binary()}) :: binary()
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
