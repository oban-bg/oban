defmodule Oban.Config do
  @moduledoc """
  The Config struct validates and encapsulates Oban instance state.

  Typically, you won't use the Config module directly. Oban automatically creates a Config struct
  on initialization and passes it through to all supervised children with the `:conf` key.

  To fetch a running Oban supervisor's config, see `Oban.config/1`.
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
          prefix: false | String.t(),
          queues: false | [{atom() | binary(), pos_integer() | Keyword.t()}],
          repo: module(),
          shutdown_grace_period: timeout(),
          stage_interval: timeout(),
          testing: :disabled | :inline | :manual
        }

  defstruct dispatch_cooldown: 5,
            engine: Oban.Engines.Basic,
            get_dynamic_repo: nil,
            log: false,
            name: Oban,
            node: nil,
            notifier: Oban.Notifiers.Postgres,
            peer: Oban.Peers.Postgres,
            plugins: [],
            prefix: "public",
            queues: [],
            repo: nil,
            shutdown_grace_period: :timer.seconds(15),
            stage_interval: :timer.seconds(1),
            testing: :disabled

  @cron_keys ~w(crontab timezone)a
  @log_levels ~w(false emergency alert critical error warning warn notice info debug)a
  @testing_modes ~w(manual inline disabled)a
  @renamed [{:engine, Oban.Queue.BasicEngine}, {:notifier, Oban.PostgresNotifier}]

  @doc """
  Generate a Config struct after normalizing and verifying Oban options.

  See `Oban.start_link/1` for a comprehensive description of available options.

  ## Example

  Generate a minimal config with only a `:repo`:

      Oban.Config.new(repo: Oban.Test.Repo)
  """
  @spec new([Oban.option()]) :: t()
  def new(opts) when is_list(opts) do
    opts = normalize(opts)

    opts =
      if opts[:engine] == Oban.Engines.Lite do
        opts
        |> Keyword.put(:prefix, false)
        |> Keyword.put_new(:notifier, Oban.Notifiers.PG)
        |> Keyword.put_new(:peer, Oban.Peers.Isolated)
      else
        opts
      end

    opts =
      if opts[:testing] in [:manual, :inline] do
        opts
        |> Keyword.put(:queues, [])
        |> Keyword.put(:peer, Oban.Peers.Disabled)
        |> Keyword.put(:plugins, [])
        |> Keyword.put(:stage_interval, :infinity)
      else
        opts
      end

    Validation.validate!(opts, &validate/1)

    struct!(__MODULE__, opts)
  end

  @doc """
  Verify configuration options.

  This helper is used by `new/1`, and therefore by `Oban.start_link/1`, to verify configuration
  options when an Oban supervisor starts. It is provided publicly to aid in configuration testing,
  as `test` config may differ from `prod` config.

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
    opts = normalize(opts)

    Validation.validate(opts, &validate_opt(opts, &1))
  end

  @doc false
  @spec get_engine(t()) :: module()
  def get_engine(%__MODULE__{engine: engine, testing: testing}) do
    if Process.get(:oban_testing, testing) == :inline do
      Oban.Engines.Inline
    else
      engine
    end
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

  defp validate_opt(_opts, {:dispatch_cooldown, cooldown}) do
    Validation.validate_integer(:dispatch_cooldown, cooldown)
  end

  defp validate_opt(_opts, {:engine, engine}) do
    if Code.ensure_loaded?(engine) and function_exported?(engine, :init, 2) do
      :ok
    else
      {:error, "expected :engine to be an Oban.Queue.Engine, got: #{inspect(engine)}"}
    end
  end

  defp validate_opt(_opts, {:get_dynamic_repo, fun}) do
    if is_nil(fun) or is_function(fun, 0) do
      :ok
    else
      {:error,
       "expected :get_dynamic_repo to be nil or a zero arity function, got: #{inspect(fun)}"}
    end
  end

  defp validate_opt(_opts, {:notifier, notifier}) do
    if Code.ensure_loaded?(notifier) and function_exported?(notifier, :listen, 2) do
      :ok
    else
      {:error, "expected :notifier to be an Oban.Notifier, got: #{inspect(notifier)}"}
    end
  end

  defp validate_opt(_opts, {:name, _}), do: :ok

  defp validate_opt(_opts, {:node, node}) do
    if is_binary(node) and String.trim(node) != "" do
      :ok
    else
      {:error, "expected :node to be a non-empty binary, got: #{inspect(node)}"}
    end
  end

  defp validate_opt(_opts, {:peer, peer}) do
    if peer == false or Code.ensure_loaded?(peer) do
      :ok
    else
      {:error, "expected :peer to be false or an Oban.Peer, got: #{inspect(peer)}"}
    end
  end

  defp validate_opt(_opts, {:plugins, plugins}) do
    Validation.validate(:plugins, plugins, &validate_plugin/1)
  end

  defp validate_opt(_opts, {:prefix, prefix}) do
    if prefix == false or (is_binary(prefix) and Regex.match?(~r/^[a-z0-9_]+$/i, prefix)) do
      :ok
    else
      {:error, "expected :prefix to be false or an alphanumeric string, got: #{inspect(prefix)}"}
    end
  end

  defp validate_opt(opts, {:queues, queues}) do
    if Keyword.keyword?(queues) do
      # Queue validation requires an engine and partial configuration. Only the engine matters,
      # but the other values are required for the struct.
      conf_opts =
        opts
        |> Keyword.take([:engine, :name, :node, :repo])
        |> Keyword.put_new(:engine, Oban.Engines.Basic)
        |> Keyword.put_new(:repo, None)

      conf = struct!(__MODULE__, conf_opts)

      Validation.validate(queues, &validate_queue(conf, &1))
    else
      {:error, "expected :queues to be a keyword list, got: #{inspect(queues)}"}
    end
  end

  defp validate_opt(_opts, {:repo, repo}) do
    if Code.ensure_loaded?(repo) and function_exported?(repo, :config, 0) do
      :ok
    else
      {:error, "expected :repo to be an Ecto.Repo, got: #{inspect(repo)}"}
    end
  end

  defp validate_opt(_opts, {:shutdown_grace_period, period}) do
    Validation.validate_integer(:shutdown_grace_period, period, min: 0)
  end

  defp validate_opt(_opts, {:stage_interval, interval}) do
    Validation.validate_timeout(:stage_interval, interval)
  end

  defp validate_opt(_opts, {:testing, testing}) do
    if testing in @testing_modes do
      :ok
    else
      {:error, "expected :testing to be a known mode, got: #{inspect(testing)}"}
    end
  end

  defp validate_opt(_opts, {:log, log}) do
    if log in @log_levels do
      :ok
    else
      {:error, "expected :log to be one of #{inspect(@log_levels)}, got: #{inspect(log)}"}
    end
  end

  defp validate_opt(_opts, option) do
    {:unknown, option, __MODULE__}
  end

  defp validate_plugin(plugin) when not is_tuple(plugin), do: validate_plugin({plugin, []})

  defp validate_plugin({plugin, opts}) do
    name = inspect(plugin)

    cond do
      not is_atom(plugin) ->
        {:error, "plugin #{name} is not a valid module"}

      not Code.ensure_loaded?(plugin) ->
        {:error, "plugin #{name} could not be loaded"}

      not function_exported?(plugin, :init, 1) ->
        {:error, "plugin #{name} is invalid because it's missing an `init/1` function"}

      not Keyword.keyword?(opts) ->
        {:error, "expected #{name} options to be a keyword list, got: #{inspect(opts)}"}

      function_exported?(plugin, :validate, 1) ->
        plugin.validate(opts)

      true ->
        :ok
    end
  end

  defp validate_queue(conf, {name, opts}) do
    cond do
      is_integer(opts) and opts > 0 ->
        :ok

      Keyword.keyword?(opts) ->
        opts =
          opts
          |> Keyword.delete(:dispatch_cooldown)
          |> Keyword.put(:validate, true)

        case conf.engine.init(conf, opts) do
          {:ok, _meta} ->
            :ok

          {:error, error} ->
            {:error, "queue #{inspect(name)}, " <> Exception.message(error)}
        end

      true ->
        {:error,
         "expected queue #{inspect(name)} opts to be a positive integer limit or a " <>
           "keyword list, got: #{inspect(opts)}"}
    end
  end

  # Normalization

  defp normalize(opts) do
    opts
    |> crontab_to_plugin()
    |> peer_to_disabled()
    |> Keyword.put_new(:node, node_name())
    |> Keyword.update(:queues, [], &normalize_queues/1)
    |> Keyword.update(:plugins, [], &normalize_plugins/1)
    |> Keyword.delete(:circuit_backoff)
    |> stager_to_interval()
    |> Enum.reject(&(&1 in @renamed))
  end

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

  defp stager_to_interval(opts) do
    cond do
      Keyword.has_key?(opts, :poll_interval) ->
        opts
        |> Keyword.put_new(:stage_interval, opts[:poll_interval])
        |> Keyword.delete(:poll_interval)

      Keyword.keyword?(opts[:plugins]) ->
        {stager_opts, opts} = pop_in(opts, [:plugins, Oban.Plugins.Stager])

        if is_list(stager_opts) and Keyword.has_key?(stager_opts, :interval) do
          Keyword.put_new(opts, :stage_interval, stager_opts[:interval])
        else
          opts
        end

      true ->
        opts
    end
  end

  defp peer_to_disabled(opts) do
    if opts[:peer] == false or opts[:plugins] == false do
      Keyword.put(opts, :peer, Oban.Peers.Disabled)
    else
      opts
    end
  end

  defp normalize_queues(queues) when is_list(queues) do
    for {name, value} <- queues do
      opts = if is_integer(value), do: [limit: value], else: value

      {name, opts}
    end
  end

  defp normalize_queues(queues), do: queues || []

  # Manually specified plugins will be overwritten by auto-specified plugins unless we reverse the
  # plugin list. The order doesn't matter as they are supervised one-for-one.
  defp normalize_plugins(plugins) when is_list(plugins) do
    plugins
    |> Enum.map(&if is_atom(&1), do: {&1, []}, else: &1)
    |> Enum.reverse()
    |> Enum.uniq()
  end

  defp normalize_plugins(plugins), do: plugins || []
end
