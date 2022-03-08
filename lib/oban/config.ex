defmodule Oban.Config do
  @moduledoc """
  The Config struct validates and encapsulates Oban instance state.

  Options passed to `Oban.start_link/1` are validated and stored in a config struct. Internal
  modules and plugins are always passed the config with a `:conf` key.
  """

  alias Oban.Validation

  @type t :: %__MODULE__{
          dispatch_cooldown: pos_integer(),
          engine: module(),
          get_dynamic_repo: nil | (() -> pid() | atom()),
          log: false | Logger.level(),
          name: Oban.name(),
          node: String.t(),
          notifier: module(),
          peer: false | module(),
          plugins: false | [module() | {module() | Keyword.t()}],
          prefix: String.t(),
          queues: false | [{atom() | binary(), pos_integer() | Keyword.t()}],
          repo: module(),
          shutdown_grace_period: timeout()
        }

  @enforce_keys [:node, :repo]
  defstruct dispatch_cooldown: 5,
            engine: Oban.Queue.BasicEngine,
            notifier: Oban.Notifiers.Postgres,
            name: Oban,
            node: nil,
            peer: Oban.Peer,
            plugins: [],
            prefix: "public",
            queues: [],
            repo: nil,
            shutdown_grace_period: :timer.seconds(15),
            log: false,
            get_dynamic_repo: nil

  @doc false
  @spec new([Oban.option()]) :: t()
  def new(opts) when is_list(opts) do
    opts = normalize(opts)

    Validation.validate!(opts, &validate_option/1)

    opts =
      opts
      |> Keyword.update!(:queues, &normalize_queues/1)
      |> Keyword.update!(:plugins, &normalize_plugins/1)

    struct!(__MODULE__, opts)
  end

  @doc """
  Utility for verifying configuration options.

  This helper is used by `new/1`, and therefore by `Oban.init/1`, to verify configuration options
  when an Oban supervisor starts. It is provided publicly to aid in configuration testing, as
  `test` config may differ from `prod` config.

  # Example

  Validating top level options:

      iex> Oban.Config.validate(name: Oban)
      :ok

      iex> Oban.Config.validate(name: Oban, log: false)
      :ok

      iex> Oban.Config.validate(node: {:not, :binary})
      {:error, "expected :node to be a non-empty binary, got: {:not, :binary}"}

      iex> Oban.Config.validate(plugins: true)
      {:error, "expected :plugins to be a list, got: true"}

  Validating plugin options:

      iex> Oban.Config.validate(plugins: [{Oban.Plugins.Pruner, max_age: 60}])
      :ok

      iex> Oban.Config.validate(plugins: [{Oban.Plugins.Pruner, max_age: 0}])
      {:error, "expected :max_age to be a positive integer, got: 0"}
  """
  @spec validate([Oban.option()]) :: :ok | {:error, String.t()}
  def validate(opts) when is_list(opts) do
    opts
    |> normalize()
    |> Validation.validate(&validate_option/1)
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

  # Validation

  defp is_pos_integer(interval), do: is_integer(interval) and interval > 0

  defp validate_option({:dispatch_cooldown, cooldown}) do
    if is_pos_integer(cooldown) do
      :ok
    else
      {:error, "expected :dispatch_cooldown to be a positive integer, got: #{inspect(cooldown)}"}
    end
  end

  defp validate_option({:engine, engine}) do
    if Code.ensure_loaded?(engine) and function_exported?(engine, :init, 2) do
      :ok
    else
      {:error, "expected :engine to be an Oban.Queue.Engine, got: #{inspect(engine)}"}
    end
  end

  defp validate_option({:notifier, notifier}) do
    if Code.ensure_loaded?(notifier) and function_exported?(notifier, :listen, 2) do
      :ok
    else
      {:error, "expected :notifier to be an Oban.Notifier, got: #{inspect(notifier)}"}
    end
  end

  defp validate_option({:name, _}), do: :ok

  defp validate_option({:node, node}) do
    if is_binary(node) and String.trim(node) != "" do
      :ok
    else
      {:error, "expected :node to be a non-empty binary, got: #{inspect(node)}"}
    end
  end

  defp validate_option({:peer, peer}) do
    if peer == false or Code.ensure_loaded?(peer) do
      :ok
    else
      {:error, "expected :peer to be false or an Oban.Peer, got: #{inspect(peer)}"}
    end
  end

  defp validate_option({:plugins, plugins}) do
    if is_list(plugins) do
      Validation.validate(plugins, &validate_plugin/1)
    else
      {:error, "expected :plugins to be a list, got: #{inspect(plugins)}"}
    end
  end

  defp validate_option({:prefix, prefix}) do
    if is_binary(prefix) and Regex.match?(~r/^[a-z0-9_]+$/i, prefix) do
      :ok
    else
      {:error, "expected :prefix to be an alphanumeric string, got: #{inspect(prefix)}"}
    end
  end

  defp validate_option({:queues, queues}) do
    if Keyword.keyword?(queues) do
      Validation.validate(queues, &validate_queue/1)
    else
      {:error, "expected :queues to be a keyword list, got: #{inspect(queues)}"}
    end
  end

  defp validate_option({:repo, repo}) do
    if Code.ensure_loaded?(repo) and function_exported?(repo, :config, 0) do
      :ok
    else
      {:error, "expected :repo to be an Ecto.Repo, got: #{inspect(repo)}"}
    end
  end

  defp validate_option({:shutdown_grace_period, period}) do
    if is_pos_integer(period) do
      :ok
    else
      {:error,
       "expected :shutdown_grace_period to be a positive integer, got: #{inspect(period)}"}
    end
  end

  @log_levels ~w(false emergency alert critical error warning warn notice info debug)a

  defp validate_option({:log, log}) do
    if log in @log_levels do
      :ok
    else
      {:error, "expected :log to be one of #{inspect(@log_levels)}, got: #{inspect(log)}"}
    end
  end

  defp validate_option({:get_dynamic_repo, fun}) do
    if is_nil(fun) or is_function(fun, 0) do
      :ok
    else
      {:error,
       "expected :get_dynamic_repo to be nil or a zero arity function, got: #{inspect(fun)}"}
    end
  end

  defp validate_option(option) do
    {:error, "unknown option provided #{inspect(option)}"}
  end

  defp validate_plugin(plugin) when not is_tuple(plugin), do: validate_plugin({plugin, []})

  defp validate_plugin({plugin, opts}) do
    cond do
      not is_atom(plugin) ->
        {:error, "plugin #{inspect(plugin)} is not a valid module"}

      not Code.ensure_loaded?(plugin) ->
        {:error, "plugin #{plugin} could not be loaded"}

      not function_exported?(plugin, :validate, 1) ->
        {:error, "plugin #{plugin} is invalid because it's missing a `validate/1` function"}

      not function_exported?(plugin, :init, 1) ->
        {:error, "plugin #{plugin} is invalid because it's missing an `init/1` function"}

      not Keyword.keyword?(opts) ->
        {:error, "expected options to be a keyword, got: #{inspect(opts)}"}

      true ->
        plugin.validate(opts)
    end
  end

  defp validate_queue({name, opts}) do
    if is_pos_integer(opts) or Keyword.keyword?(opts) do
      :ok
    else
      {:error,
       "expected queue #{inspect(name)} opts to be a positive integer limit or a " <>
         "keyword list, got: #{inspect(opts)}"}
    end
  end

  # Normalization

  defp normalize(opts) do
    opts
    |> crontab_to_plugin()
    |> poll_interval_to_plugin()
    |> Keyword.put_new(:node, node_name())
    |> Keyword.update(:plugins, [], &(&1 || []))
    |> Keyword.update(:queues, [], &(&1 || []))
    |> Keyword.delete(:circuit_backoff)
    |> Enum.reject(&(&1 == {:notifier, Oban.PostgresNotifier}))
  end

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

  defp normalize_queues(queues) do
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
