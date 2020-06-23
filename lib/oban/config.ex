defmodule Oban.Config do
  @moduledoc false

  alias Oban.Crontab.Cron

  use Agent

  @type cronjob :: {Cron.t(), module(), Keyword.t()}

  @type t :: %__MODULE__{
          circuit_backoff: timeout(),
          crontab: [cronjob()],
          dispatch_cooldown: pos_integer(),
          name: atom(),
          node: binary(),
          plugins: [module() | {module() | Keyword.t()}],
          poll_interval: pos_integer(),
          prefix: binary(),
          queues: [{atom(), pos_integer()}],
          repo: module(),
          shutdown_grace_period: timeout(),
          timezone: Calendar.time_zone(),
          log: false | Logger.level()
        }

  @type option :: {:name, module()} | {:conf, t()}

  @enforce_keys [:node, :repo]
  defstruct circuit_backoff: :timer.seconds(30),
            crontab: [],
            dispatch_cooldown: 5,
            name: Oban,
            node: nil,
            plugins: [Oban.Plugins.FixedPruner],
            poll_interval: :timer.seconds(1),
            prefix: "public",
            queues: [],
            repo: nil,
            shutdown_grace_period: :timer.seconds(15),
            timezone: "Etc/UTC",
            log: false

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
      |> Keyword.put(:crontab, opts[:crontab] || [])
      |> Keyword.put(:plugins, opts[:plugins] || [])
      |> Keyword.put(:queues, opts[:queues] || [])

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

  @spec to_ident(t()) :: binary()
  def to_ident(%__MODULE__{name: name, node: node}) do
    to_string(name) <> "." <> to_string(node)
  end

  @spec match_ident?(t(), binary()) :: boolean()
  def match_ident?(%__MODULE__{} = conf, ident) when is_binary(ident) do
    to_ident(conf) == ident
  end

  # Helpers

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

  defp validate_opt!({:plugins, plugins}) do
    unless is_list(plugins) and Enum.all?(plugins, &valid_plugin?/1) do
      raise ArgumentError, "expected a list of modules or {module, keyword} tuples"
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

  defp validate_opt!({:log, log}) do
    unless log in ~w(false error warn info debug)a do
      raise ArgumentError, "expected :log to be `false` or a log level"
    end
  end

  defp validate_opt!(option) do
    raise ArgumentError, "unknown option provided #{inspect(option)}"
  end

  defp valid_crontab?({expression, worker}) do
    valid_crontab?({expression, worker, []})
  end

  defp valid_crontab?({expression, worker, opts}) do
    is_binary(expression) and
      Code.ensure_loaded?(worker) and
      function_exported?(worker, :perform, 1) and
      Keyword.keyword?(opts)
  end

  defp valid_crontab?(_crontab), do: false

  defp valid_queue?({_name, limit}), do: is_integer(limit) and limit > 0

  defp valid_plugin?({plugin, opts}) do
    is_atom(plugin) and
      Code.ensure_loaded?(plugin) and
      function_exported?(plugin, :init, 1) and
      Keyword.keyword?(opts)
  end

  defp valid_plugin?(plugin), do: valid_plugin?({plugin, []})

  defp parse_crontab(crontab) do
    for tuple <- crontab do
      case tuple do
        {expression, worker} ->
          {Cron.parse!(expression), worker, []}

        {expression, worker, opts} ->
          {Cron.parse!(expression), worker, opts}
      end
    end
  end
end
