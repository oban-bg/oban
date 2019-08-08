defmodule Oban.Config do
  @moduledoc false

  use Agent

  @type prune :: :disabled | {:maxlen, pos_integer()} | {:maxage, pos_integer()}

  @type t :: %__MODULE__{
          name: atom(),
          node: binary(),
          poll_interval: pos_integer(),
          prefix: binary(),
          prune: prune(),
          prune_interval: pos_integer(),
          prune_limit: pos_integer(),
          queues: [{atom(), pos_integer()}],
          repo: module(),
          shutdown_grace_period: timeout(),
          verbose: boolean()
        }

  @type option :: {:name, module()} | {:conf, t()}

  @enforce_keys [:node, :repo]
  defstruct name: Oban,
            node: nil,
            poll_interval: :timer.seconds(1),
            prefix: "public",
            prune: :disabled,
            prune_interval: :timer.minutes(1),
            prune_limit: 5_000,
            queues: [default: 10],
            repo: nil,
            shutdown_grace_period: :timer.seconds(15),
            verbose: true

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

  @spec get(atom()) :: t()
  def get(name), do: Agent.get(name, & &1)

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

  defp validate_opt!({:name, name}) do
    unless is_atom(name) do
      raise ArgumentError, "expected :name to be a module or atom"
    end
  end

  defp validate_opt!({:node, node}) do
    unless is_binary(node) and node != "" do
      raise ArgumentError, "expected :node to be a non-empty binary"
    end
  end

  defp validate_opt!({:poll_interval, interval}) do
    unless is_integer(interval) and interval > 0 do
      raise ArgumentError, "expected :poll_interval to be a positive integer"
    end
  end

  defp validate_opt!({:prefix, prefix}) do
    unless is_binary(prefix) and Regex.match?(~r/^[a-z0-9_]+$/i, prefix) do
      raise ArgumentError, "expected :prefix to be a binary with alphanumeric characters"
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

  defp validate_opt!({:prune_limit, limit}) do
    unless is_integer(limit) and limit > 0 do
      raise ArgumentError, "expected :prune_interval to be a positive integer"
    end
  end

  defp validate_opt!({:queues, queues}) do
    unless Keyword.keyword?(queues) and Enum.all?(queues, &valid_queue?/1) do
      raise ArgumentError, "expected :queues to be a keyword list of {atom, integer} pairs"
    end
  end

  defp validate_opt!({:repo, repo}) do
    unless Code.ensure_compiled?(repo) and function_exported?(repo, :__adapter__, 0) do
      raise ArgumentError, "expected :repo to be an Ecto.Repo"
    end
  end

  defp validate_opt!({:shutdown_grace_period, interval}) do
    unless is_integer(interval) and interval > 0 do
      raise ArgumentError, "expected :shutdown_grace_period to be a positive integer"
    end
  end

  defp validate_opt!({:verbose, verbose}) do
    unless is_boolean(verbose) do
      raise ArgumentError, "expected :verbose to be a boolean"
    end
  end

  defp validate_opt!(option) do
    raise ArgumentError, "unknown option provided #{inspect(option)}"
  end

  defp valid_queue?({_name, size}), do: is_integer(size) and size > 0
end
