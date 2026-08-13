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
          insert_trigger: boolean(),
          name: Oban.name(),
          node: String.t(),
          notifier: {module(), Keyword.t()},
          peer: {module(), Keyword.t()},
          plugins: [module() | {module(), Keyword.t()}],
          prefix: false | String.t(),
          queues: Keyword.t(Keyword.t()),
          repo: module(),
          shutdown_grace_period: non_neg_integer(),
          stager: false | {module(), Keyword.t()},
          testing: :disabled | :inline | :manual
        }

  defstruct dispatch_cooldown: 5,
            engine: nil,
            get_dynamic_repo: nil,
            insert_trigger: true,
            log: false,
            name: nil,
            node: nil,
            notifier: nil,
            peer: nil,
            plugins: [],
            prefix: "public",
            queues: [],
            repo: nil,
            shutdown_grace_period: :timer.seconds(15),
            stager: {Oban.Stager, []},
            testing: :disabled

  @cron_keys ~w(crontab timezone)a
  @log_levels ~w(false emergency alert critical error warning warn notice info debug)a
  @repo_opts [log: :log, dynamic_repo: :get_dynamic_repo]
  @testing_modes ~w(manual inline disabled)a

  @service_plugins [
    cron: Oban.Cron,
    pruner: Oban.Pruner,
    lifeline: Oban.Lifeline,
    reindexer: Oban.Reindexer
  ]

  @renamed_modules [engine: Oban.Queue.BasicEngine, notifier: {Oban.PostgresNotifier, []}]

  @renamed_plugins [
    {Oban.Plugins.Cron, Oban.Cron},
    {Oban.Plugins.Lifeline, Oban.Lifeline},
    {Oban.Plugins.Pruner, Oban.Pruner},
    {Oban.Plugins.Reindexer, Oban.Reindexer}
  ]

  @doc """
  Generate a Config struct after normalizing and verifying Oban options.

  See `Oban.start_link/1` for a comprehensive description of available options.

  ## Example

  Generate a minimal config with only a `:repo`:

      Oban.Config.new(repo: Oban.Test.Repo)
  """
  @spec new([Oban.option()]) :: t()
  def new(opts) when is_list(opts) do
    opts =
      opts
      |> normalize()
      |> Keyword.put_new(:engine, Oban.Engines.Basic)
      |> Keyword.put_new(:name, Oban)

    opts =
      case opts[:engine] do
        Oban.Engines.Lite ->
          opts
          |> Keyword.put(:prefix, false)
          |> Keyword.put_new(:notifier, {Oban.Notifiers.PG, []})
          |> Keyword.put_new(:peer, {Oban.Peers.Isolated, []})

        Oban.Engines.Dolphin ->
          opts
          |> Keyword.put(:prefix, false)
          |> Keyword.put_new(:notifier, {Oban.Notifiers.PG, []})
          |> Keyword.put_new(:peer, {Oban.Peers.Database, []})

        _ ->
          opts
          |> Keyword.put_new(:notifier, {Oban.Notifiers.Postgres, []})
          |> Keyword.put_new(:peer, {Oban.Peers.Database, []})
      end

    opts =
      if opts[:testing] in [:manual, :inline] do
        opts
        |> Keyword.put(:peer, {Oban.Peers.Isolated, [leader?: false]})
        |> Keyword.put(:plugins, [])
        |> Keyword.put(:queues, [])
        |> Keyword.put(:stager, false)
      else
        opts
      end

    with {:error, reason} <- validate(opts) do
      raise ArgumentError, reason
    end

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

      iex> Oban.Config.validate(name: Oban, prefix: "private")
      :ok

      iex> Oban.Config.validate(node: {:not, :binary})
      {:error, "expected :node to be a binary, got: {:not, :binary}"}

      iex> Oban.Config.validate(plugins: true)
      {:error, "invalid value for :plugins, expected :plugins to be a list, got: true"}

  Validating plugin options:

      iex> Oban.Config.validate(plugins: [{Oban.Pruner, max_age: {1, :day}}])
      :ok

      iex> Oban.Config.validate(plugins: [{Oban.Pruner, max_age: 0}])
      {:error, "invalid value for :plugins, expected :max_age to be a positive integer or {amount, unit} tuple, got: 0"}
  """
  @spec validate([Oban.option()]) :: :ok | {:error, String.t()}
  def validate(opts) when is_list(opts) do
    with :ok <- validate_unique_opts(opts) do
      opts = normalize(opts)

      Validation.validate_schema(opts,
        dispatch_cooldown: :pos_integer,
        engine: {:behaviour, Oban.Engine},
        get_dynamic_repo: {:or, [:falsy, {:function, 0}, :mfa]},
        insert_trigger: :boolean,
        log: {:enum, @log_levels},
        name: :any,
        node: {:pattern, ~r/^\S+$/},
        notifier: {:behaviour, Oban.Notifier},
        peer: {:or, [:falsy, {:behaviour, Oban.Peer}]},
        plugins: {:custom, &validate_plugins/1},
        prefix: {:or, [:falsy, :string]},
        queues: {:custom, &validate_queues(opts, &1)},
        repo: {:module, [config: 0]},
        shutdown_grace_period: :non_neg_integer,
        stager: {:custom, &validate_stager/1},
        testing: {:enum, @testing_modes}
      )
    end
  end

  @doc false
  @spec get_engine(t()) :: module()
  def get_engine(%__MODULE__{engine: engine, testing: :disabled}), do: engine

  def get_engine(%__MODULE__{engine: engine, testing: testing}) do
    pids = [self() | Process.get(:"$callers", [])]

    if Enum.any?(pids, &inline_testing?(&1, testing)) do
      Oban.Engines.Inline
    else
      engine
    end
  end

  defp inline_testing?(pid, default) do
    case Process.info(pid, :dictionary) do
      {:dictionary, dictionary} -> Keyword.get(dictionary, :oban_testing, default) == :inline
      _ -> false
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

  defp validate_plugins(plugins) do
    with :ok <- validate_unique_plugins(plugins) do
      Validation.validate(:plugins, plugins, &validate_plugin/1)
    end
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

  defp validate_stager({module, opts}) when is_atom(module) do
    name = inspect(module)

    cond do
      not Code.ensure_loaded?(module) ->
        {:error, "stager #{name} could not be loaded"}

      not Keyword.keyword?(opts) ->
        {:error, "expected #{name} options to be a keyword list, got: #{inspect(opts)}"}

      function_exported?(module, :validate, 1) ->
        module.validate(opts)

      true ->
        :ok
    end
  end

  defp validate_stager(false), do: :ok

  defp validate_stager(stager) do
    {:error, "expected :stager to be a module or {module, opts} tuple, got: #{inspect(stager)}"}
  end

  defp validate_queues(opts, queues) do
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

  defp validate_unique_opts(opts) do
    keys = Keyword.keys(opts)
    dupe = keys -- Enum.uniq(keys)

    if Enum.empty?(dupe) do
      :ok
    else
      {:error, "found duplicate options: #{inspect(dupe)}"}
    end
  end

  defp validate_unique_plugins(plugins) when is_list(plugins) do
    modules =
      Enum.map(plugins, fn
        {module, _opts} -> module
        module -> module
      end)

    dupe = modules -- Enum.uniq(modules)

    if Enum.empty?(dupe) do
      :ok
    else
      {:error, "found duplicate plugins: #{inspect(dupe)}"}
    end
  end

  defp validate_unique_plugins(_plugins), do: :ok

  # Normalization

  defp normalize(opts) do
    opts
    |> normalize_repo()
    |> normalize_notifier()
    |> normalize_peer()
    |> normalize_stager()
    |> normalize_queues()
    |> normalize_plugins()
    |> Keyword.delete(:circuit_backoff)
    |> Keyword.put_new(:node, node_name())
    |> Enum.reject(&(&1 in @renamed_modules))
  end

  defp normalize_repo(opts) do
    case Keyword.get(opts, :repo) do
      {repo, repo_opts} when is_atom(repo) and is_list(repo_opts) ->
        opts
        |> Keyword.put(:repo, repo)
        |> merge_repo_opts(repo_opts)

      _ ->
        opts
    end
  end

  defp merge_repo_opts(opts, repo_opts) do
    Enum.reduce(repo_opts, opts, fn {key, value}, opts ->
      Keyword.put(opts, Keyword.get(@repo_opts, key, key), value)
    end)
  end

  defp normalize_notifier(opts) do
    case Keyword.get(opts, :notifier) do
      module when is_atom(module) and not is_nil(module) ->
        Keyword.put(opts, :notifier, {module, []})

      _ ->
        opts
    end
  end

  defp normalize_peer(opts) do
    peer = opts[:peer]

    cond do
      peer == false or opts[:plugins] == false ->
        Keyword.put(opts, :peer, {Oban.Peers.Isolated, [leader?: false]})

      peer == Oban.Peers.Postgres ->
        Keyword.put(opts, :peer, {Oban.Peers.Database, []})

      match?({Oban.Peers.Postgres, _}, peer) ->
        Keyword.put(opts, :peer, put_elem(peer, 0, Oban.Peers.Database))

      is_atom(peer) and not is_nil(peer) ->
        Keyword.put(opts, :peer, {peer, []})

      true ->
        opts
    end
  end

  defp normalize_stager(opts) do
    {stag_interval, opts} = Keyword.pop(opts, :stage_interval)
    {poll_interval, opts} = Keyword.pop(opts, :poll_interval)
    {plugin_opts, opts} = pop_stager_plugin(opts)

    legacy_interval = stag_interval || poll_interval || plugin_opts[:interval]

    stager =
      case Keyword.get(opts, :stager, []) do
        stager when stager in [false, nil] ->
          stager

        stager ->
          {module, stager_opts} = normalize_service(stager, Oban.Stager)

          {module, put_legacy_interval(stager_opts, legacy_interval)}
      end

    Keyword.put(opts, :stager, stager)
  end

  defp pop_stager_plugin(opts) do
    case Keyword.get(opts, :plugins) do
      plugins when is_list(plugins) ->
        {stagers, plugins} = Enum.split_with(plugins, &stager_plugin?/1)

        {stager_plugin_opts(stagers), Keyword.put(opts, :plugins, plugins)}

      _plugins ->
        {[], opts}
    end
  end

  defp stager_plugin?({Oban.Stager, _opts}), do: true
  defp stager_plugin?(plugin), do: plugin == Oban.Stager

  defp stager_plugin_opts([{_module, opts} | _rest]) when is_list(opts), do: opts
  defp stager_plugin_opts(_stagers), do: []

  defp put_legacy_interval(stager_opts, interval)
       when is_list(stager_opts) and not is_nil(interval) do
    Keyword.put_new(stager_opts, :interval, interval)
  end

  defp put_legacy_interval(stager_opts, _interval), do: stager_opts

  defp normalize_queues(opts) do
    case Keyword.get(opts, :queues) do
      {module, queue_opts} when is_atom(module) and is_list(queue_opts) ->
        opts
        |> Keyword.put(:queues, [])
        |> put_plugin({module, queue_opts})

      queues when is_list(queues) ->
        normalized =
          for {name, value} <- queues do
            opts = if is_integer(value), do: [limit: value], else: value

            {name, opts}
          end

        Keyword.put(opts, :queues, normalized)

      queues when queues in [nil, false] ->
        Keyword.put(opts, :queues, [])

      _other ->
        opts
    end
  end

  # Manually specified plugins will be overwritten by auto-specified plugins unless we reverse the
  # plugin list. The order doesn't matter as they are supervised one-for-one.
  defp normalize_plugins(opts) do
    opts
    |> normalize_crontab()
    |> normalize_services()
    |> Keyword.update(:plugins, [], fn
      plugins when is_list(plugins) ->
        renamer = fn
          {module, opts} -> {rename_plugin(module), opts}
          module when is_atom(module) -> {rename_plugin(module), []}
          other -> other
        end

        plugins
        |> Enum.map(renamer)
        |> Enum.reverse()
        |> Enum.uniq()

      plugins ->
        plugins || []
    end)
  end

  defp rename_plugin(module), do: Keyword.get(@renamed_plugins, module, module)

  defp normalize_crontab(opts) do
    case {opts[:plugins], opts[:crontab]} do
      {plugins, [_ | _]} when is_list(plugins) or is_nil(plugins) ->
        {cron_opts, base_opts} = Keyword.split(opts, @cron_keys)

        plugin = {Oban.Cron, cron_opts}

        Keyword.update(base_opts, :plugins, [plugin], &[plugin | &1])

      _ ->
        Keyword.drop(opts, @cron_keys)
    end
  end

  defp normalize_services(opts) do
    Enum.reduce(@service_plugins, opts, fn {key, module}, opts ->
      case Keyword.fetch(opts, key) do
        :error ->
          opts

        {:ok, false} ->
          Keyword.delete(opts, key)

        {:ok, value} ->
          opts
          |> Keyword.delete(key)
          |> put_service_plugin(normalize_service(value, module))
      end
    end)
  end

  defp normalize_service({module, opts}, _default) when is_atom(module), do: {module, opts}
  defp normalize_service(module, _default) when is_atom(module), do: {module, []}
  defp normalize_service(opts, module), do: {module, opts}

  defp put_plugin(opts, plugin) do
    case Keyword.get(opts, :plugins) do
      plugins when is_list(plugins) -> Keyword.put(opts, :plugins, [plugin | plugins])
      _falsy -> Keyword.put(opts, :plugins, [plugin])
    end
  end

  defp put_service_plugin(opts, plugin) do
    case Keyword.get(opts, :plugins) do
      false -> opts
      _plug -> put_plugin(opts, plugin)
    end
  end
end
