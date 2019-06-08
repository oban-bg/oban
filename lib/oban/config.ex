defmodule Oban.Config do
  @moduledoc false

  use Agent

  @type prune :: :disabled | {:maxlen, pos_integer()} | {:maxage, pos_integer()}

  @type t :: %__MODULE__{
          name: module(),
          node: binary(),
          poll_interval: pos_integer(),
          prune: prune(),
          prune_interval: pos_integer(),
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
            prune_interval: :timer.minutes(1),
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

    Enum.each(opts, &validate_opt!/1)

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

  defp validate_opt!({:node, node}) do
    unless is_binary(node) and node != "" do
      raise ArgumentError, "expected :poll_interval to be a positive integer"
    end
  end

  defp validate_opt!({:poll_interval, interval}) do
    unless is_integer(interval) and interval > 0 do
      raise ArgumentError, "expected :poll_interval to be a positive integer"
    end
  end

  defp validate_opt!({:prune, mode}) do
    case mode do
      :disabled -> :ok
      {:maxlen, len} when is_integer(len) and len > 0 -> :ok
      {:maxage, age} when is_integer(age) and age > 0 -> :ok
      _ -> raise ArgumentError, "unexpected :prune mode, #{inspect(mode)}"
    end
  end

  defp validate_opt!({:prune_interval, interval}) do
    unless is_integer(interval) and interval > 0 do
      raise ArgumentError, "expected :prune_interval to be a positive integer"
    end
  end

  defp validate_opt!({:queues, queues}) do
    unless Keyword.keyword?(queues) and Enum.all?(queues, &valid_queue?/1) do
      raise ArgumentError, "expected :queues to be a keyword list of {atom, integer} pairs"
    end
  end

  defp validate_opt!({:shutdown_grace_period, interval}) do
    unless is_integer(interval) and interval > 0 do
      raise ArgumentError, "expected :shutdown_grace_period to be a positive integer"
    end
  end

  defp validate_opt!(_opt), do: :ok

  defp valid_queue?({_name, size}), do: is_integer(size) and size > 0
end
