defmodule Oban.Config do
  @moduledoc false

  alias Oban.Crontab.Cron

  use Agent

  @type cronjob :: {Cron.t(), module(), Keyword.t()}

  @type prune :: :disabled | {:maxlen, pos_integer()} | {:maxage, pos_integer()}

  @type t :: %__MODULE__{
          beats_maxage: pos_integer(),
          circuit_backoff: timeout(),
          crontab: [cronjob()],
          dispatch_cooldown: pos_integer(),
          name: atom(),
          node: binary(),
          poll_interval: pos_integer(),
          prefix: binary(),
          prune: prune(),
          prune_interval: pos_integer(),
          prune_limit: pos_integer(),
          queues: [{atom(), pos_integer()}],
          repo: module(),
          rescue_after: pos_integer(),
          rescue_interval: pos_integer(),
          shutdown_grace_period: timeout(),
          timezone: Calendar.time_zone(),
          verbose: false | Logger.level()
        }

  @type option :: {:name, module()} | {:conf, t()}

  @enforce_keys [:node, :repo]
  defstruct beats_maxage: 60 * 5,
            circuit_backoff: :timer.seconds(30),
            crontab: [],
            dispatch_cooldown: 5,
            name: Oban,
            node: nil,
            poll_interval: :timer.seconds(1),
            prefix: "public",
            prune: {:maxlen, 1_000},
            prune_interval: :timer.minutes(1),
            prune_limit: 5_000,
            queues: [],
            repo: nil,
            rescue_after: 60,
            rescue_interval: :timer.minutes(1),
            shutdown_grace_period: :timer.seconds(15),
            timezone: "Etc/UTC",
            verbose: false

  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    {conf, opts} = Keyword.pop(opts, :conf)

    Agent.start_link(fn -> conf end, opts)
  end

  @spec new(Keyword.t()) :: t()
  def new(opts) when is_list(opts) do
    opts =
      opts
      |> Keyword.put_new(:node, node_name())
      |> Keyword.put(:queues, Keyword.get(opts, :queues) || [])
      |> Keyword.put(:crontab, Keyword.get(opts, :crontab) || [])

    Enum.each(opts, &validate_opt!/1)

    opts = Keyword.update(opts, :crontab, [], &parse_crontab/1)

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

  defp validate_opt!({:beats_maxage, maxage}) do
    unless is_integer(maxage) and maxage > 60 do
      raise ArgumentError, "expected :beats_maxage to be an integer greater than 60"
    end
  end

  defp validate_opt!({:circuit_backoff, interval}) do
    unless is_integer(interval) and interval > 0 do
      raise ArgumentError, "expected :circuit_backoff to be a positive integer"
    end
  end

  defp validate_opt!({:crontab, crontab}) do
    unless is_list(crontab) and Enum.all?(crontab, &valid_crontab?/1) do
      raise ArgumentError,
            "expected :crontab to be a list of {expression, worker} or " <>
              "{expression, worker, options} tuples"
    end
  end

  defp validate_opt!({:dispatch_cooldown, period}) do
    unless is_integer(period) and period > 0 do
      raise ArgumentError, "expected :dispatch_cooldown to be a positive integer"
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
    unless Code.ensure_loaded?(repo) and function_exported?(repo, :__adapter__, 0) do
      raise ArgumentError, "expected :repo to be an Ecto.Repo"
    end
  end

  defp validate_opt!({:rescue_after, interval}) do
    unless is_integer(interval) and interval > 0 do
      raise ArgumentError, "expected :rescue_after to be a positive integer"
    end
  end

  defp validate_opt!({:rescue_interval, interval}) do
    unless is_integer(interval) and interval > 0 do
      raise ArgumentError, "expected :rescue_interval to be a positive integer"
    end
  end

  defp validate_opt!({:shutdown_grace_period, interval}) do
    unless is_integer(interval) and interval > 0 do
      raise ArgumentError, "expected :shutdown_grace_period to be a positive integer"
    end
  end

  defp validate_opt!({:timezone, timezone}) do
    unless is_binary(timezone) and match?({:ok, _}, DateTime.now(timezone)) do
      raise ArgumentError, "expected :timezone to be a known timezone"
    end
  end

  defp validate_opt!({:verbose, verbose}) do
    unless verbose in ~w(false error warn info debug)a do
      raise ArgumentError, "expected :verbose to be `false` or a log level"
    end
  end

  defp validate_opt!(option) do
    raise ArgumentError, "unknown option provided #{inspect(option)}"
  end

  defp valid_crontab?({expression, worker}) do
    valid_crontab?({expression, worker, []})
  end

  defp valid_crontab?({expression, worker, options}) do
    is_binary(expression) and
      Code.ensure_loaded?(worker) and
      function_exported?(worker, :perform, 2) and
      Keyword.keyword?(options)
  end

  defp valid_crontab?(_crontab), do: false

  defp valid_queue?({_name, limit}), do: is_integer(limit) and limit > 0

  defp parse_crontab(crontab) do
    for tuple <- crontab do
      case tuple do
        {expression, worker} ->
          {Cron.parse!(expression), worker, []}

        {expression, worker, options} ->
          {Cron.parse!(expression), worker, options}
      end
    end
  end
end
