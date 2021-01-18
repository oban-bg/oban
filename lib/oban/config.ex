defmodule Oban.Config do
  @moduledoc """
  The Config struct validates and encapsulates Oban instance state.

  Options passed to `Oban.start_link/1` are validated and stored in a config struct. Internal
  modules and plugins are always passed the config with a `:conf` key.
  """

  @type t :: %__MODULE__{
          circuit_backoff: timeout(),
          dispatch_cooldown: pos_integer(),
          name: Oban.name(),
          node: binary(),
          plugins: [module() | {module() | Keyword.t()}],
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
            prefix: "public",
            queues: [],
            repo: nil,
            shutdown_grace_period: :timer.seconds(15),
            log: false,
            get_dynamic_repo: nil

  defguardp is_pos_integer(interval) when is_integer(interval) and interval > 0

  @doc false
  @spec new(Keyword.t()) :: t()
  def new(opts) when is_list(opts) do
    opts =
      opts
      |> crontab_to_plugin()
      |> poll_interval_to_plugin()
      |> Keyword.put_new(:node, node_name())
      |> Keyword.update(:plugins, [], &(&1 || []))
      |> Keyword.update(:queues, [], &(&1 || []))

    Enum.each(opts, &validate_opt!/1)

    opts =
      opts
      |> Keyword.update!(:queues, &parse_queues/1)
      |> Keyword.update!(:plugins, &normalize_plugins/1)

    struct!(__MODULE__, opts)
  end

  @doc false
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

  @doc false
  @spec to_ident(t()) :: binary()
  def to_ident(%__MODULE__{name: name, node: node}) do
    inspect(name) <> "." <> to_string(node)
  end

  @doc false
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

  defp poll_interval_to_plugin(opts) do
    case {opts[:plugins], opts[:poll_interval]} do
      {plugins, interval} when (is_list(plugins) or is_nil(plugins)) and is_integer(interval) ->
        plugin = {Oban.Plugins.Stager, interval: interval}

        opts
        |> Keyword.delete(:poll_interval)
        |> Keyword.update(:plugins, [plugin], &[plugin | &1])

      {plugins, nil} when is_list(plugins) or is_nil(plugins) ->
        plugin = Oban.Plugins.Stager

        Keyword.update(opts, :plugins, [plugin], &[plugin | &1])

      _ ->
        Keyword.drop(opts, [:poll_interval])
    end
  end

  defp validate_opt!({:circuit_backoff, backoff}) do
    unless is_pos_integer(backoff) do
      raise ArgumentError,
            "expected :circuit_backoff to be a positive integer, got: #{inspect(backoff)}"
    end
  end

  defp validate_opt!({:dispatch_cooldown, cooldown}) do
    unless is_pos_integer(cooldown) do
      raise ArgumentError,
            "expected :dispatch_cooldown to be a positive integer, got: #{inspect(cooldown)}"
    end
  end

  defp validate_opt!({:name, _}), do: :ok

  defp validate_opt!({:node, node}) do
    unless is_binary(node) and String.trim(node) != "" do
      raise ArgumentError,
            "expected :node to be a non-empty binary, got: #{inspect(node)}"
    end
  end

  defp validate_opt!({:plugins, plugins}) do
    unless is_list(plugins) and Enum.all?(plugins, &valid_plugin?/1) do
      raise ArgumentError,
            "expected :plugins to be a list of modules or {module, keyword} tuples " <>
              ", got: #{inspect(plugins)}"
    end
  end

  defp validate_opt!({:prefix, prefix}) do
    unless is_binary(prefix) and Regex.match?(~r/^[a-z0-9_]+$/i, prefix) do
      raise ArgumentError,
            "expected :prefix to be a binary with alphanumeric characters, got: #{inspect(prefix)}"
    end
  end

  defp validate_opt!({:queues, queues}) do
    unless Keyword.keyword?(queues) and Enum.all?(queues, &valid_queue?/1) do
      raise ArgumentError,
            "expected :queues to be a keyword list of {atom, integer} pairs or " <>
              "a list of {atom, keyword} pairs, got: #{inspect(queues)}"
    end
  end

  defp validate_opt!({:repo, repo}) do
    unless Code.ensure_loaded?(repo) and function_exported?(repo, :__adapter__, 0) do
      raise ArgumentError,
            "expected :repo to be an Ecto.Repo, got: #{inspect(repo)}"
    end
  end

  defp validate_opt!({:shutdown_grace_period, period}) do
    unless is_pos_integer(period) do
      raise ArgumentError,
            "expected :shutdown_grace_period to be a positive integer, got: #{inspect(period)}"
    end
  end

  @log_levels ~w(false emergency alert critical error warning warn notice info debug)a

  defp validate_opt!({:log, log}) do
    unless log in @log_levels do
      raise ArgumentError,
            "expected :log to be one of #{inspect(@log_levels)}, got: #{inspect(log)}"
    end
  end

  defp validate_opt!({:get_dynamic_repo, fun}) do
    unless is_nil(fun) or is_function(fun, 0) do
      raise ArgumentError,
            "expected :get_dynamic_repo to be nil or a zero arity function, got: #{inspect(fun)}"
    end
  end

  defp validate_opt!(option) do
    raise ArgumentError, "unknown option provided #{inspect(option)}"
  end

  defp valid_queue?({_name, opts}) do
    is_pos_integer(opts) or Keyword.keyword?(opts)
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

  # Manually specified plugins will be overwritten by auto-specified plugins unless we reverse the
  # plugin list. The order doesn't matter as they are supervised one-for-one.
  defp normalize_plugins(plugins) do
    plugins
    |> Enum.reverse()
    |> Enum.uniq_by(fn
      {module, _opts} -> module
      module -> module
    end)
  end
end
