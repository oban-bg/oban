defmodule Oban.Config do
  @moduledoc false

  @type t :: %__MODULE__{
          circuit_backoff: timeout(),
          dispatch_cooldown: pos_integer(),
          name: Oban.name(),
          node: binary(),
          plugins: [module() | {module() | Keyword.t()}],
          poll_interval: pos_integer(),
          prefix: binary(),
          queues: [{atom(), Keyword.t()}],
          repo: module(),
          shutdown_grace_period: timeout(),
          log: false | Logger.level(),
          get_dynamic_repo: nil | (() -> pid() | atom())
        }

  @type option :: {:name, module()} | {:conf, t()}

  @enforce_keys [:node, :repo]
  defstruct circuit_backoff: :timer.seconds(30),
            dispatch_cooldown: 5,
            name: Oban,
            node: nil,
            plugins: [],
            poll_interval: :timer.seconds(1),
            prefix: "public",
            queues: [],
            repo: nil,
            shutdown_grace_period: :timer.seconds(15),
            log: false,
            get_dynamic_repo: nil

  @spec new(Keyword.t()) :: t()
  def new(opts) when is_list(opts) do
    opts =
      opts
      |> crontab_to_plugin()
      |> Keyword.put_new(:node, node_name())
      |> Keyword.update(:plugins, [], &(&1 || []))
      |> Keyword.update(:queues, [], &(&1 || []))

    Enum.each(opts, &validate_opt!/1)

    opts = Keyword.update!(opts, :queues, &parse_queues/1)

    struct!(__MODULE__, opts)
  end

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
    inspect(name) <> "." <> to_string(node)
  end

  @spec match_ident?(t(), binary()) :: boolean()
  def match_ident?(%__MODULE__{} = conf, ident) when is_binary(ident) do
    to_ident(conf) == ident
  end

  # Helpers

  @cron_keys [:crontab, :timezone]

  defp crontab_to_plugin(opts) do
    case {opts[:plugins], opts[:crontab]} do
      {plugins, [_ | _]} when is_list(plugins) or is_nil(plugins) ->
        {cron_opts, base_opts} = Keyword.split(opts, @cron_keys)

        plugin = {Oban.Plugins.Cron, cron_opts}

        Keyword.update(base_opts, :plugins, [plugin], &[plugin | &1])

      _ ->
        Keyword.drop(opts, @cron_keys)
    end
  end

  defp validate_opt!({:circuit_backoff, interval}) do
    unless is_integer(interval) and interval > 0 do
      raise ArgumentError, "expected :circuit_backoff to be a positive integer"
    end
  end

  defp validate_opt!({:dispatch_cooldown, period}) do
    unless is_integer(period) and period > 0 do
      raise ArgumentError, "expected :dispatch_cooldown to be a positive integer"
    end
  end

  defp validate_opt!({:name, _}), do: :ok

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

  defp validate_opt!({:log, log}) do
    unless log in ~w(false error warn info debug)a do
      raise ArgumentError, "expected :log to be `false` or a log level"
    end
  end

  defp validate_opt!({:get_dynamic_repo, fun}) do
    unless is_nil(fun) or is_function(fun, 0) do
      raise ArgumentError, "expected :gethostname to be `nil` or a zero arity function"
    end
  end

  defp validate_opt!(option) do
    raise ArgumentError, "unknown option provided #{inspect(option)}"
  end

  defp valid_queue?({_name, opts}) do
    (is_integer(opts) and opts > 0) or Keyword.keyword?(opts)
  end

  defp valid_plugin?({plugin, opts}) do
    is_atom(plugin) and
      Code.ensure_loaded?(plugin) and
      function_exported?(plugin, :init, 1) and
      Keyword.keyword?(opts)
  end

  defp valid_plugin?(plugin), do: valid_plugin?({plugin, []})

  defp parse_queues(queues) do
    for {name, value} <- queues do
      opts = if is_integer(value), do: [limit: value], else: value

      {name, opts}
    end
  end
end
