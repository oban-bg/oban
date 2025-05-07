defmodule Oban.Repo do
  @moduledoc """
  Wrappers around `Ecto.Repo` and `Ecto.Adapters.SQL` callbacks.

  Each function resolves the correct repo instance and sets options such as `prefix` and `log`
  according to `Oban.Config`.

  > #### Meant for Extending Oban {: .warning}
  >
  > These functions should only be used when working with a repo inside engines, plugins, or other
  > extensions for Oban. Favor using your application's repo directly when querying `Oban.Job`
  > from your workers.

  ## Examples

  The first argument for every function must be an `Oban.Config` struct. Many functions pass
  configuration around as a `conf` key, and it can always be fetched with `Oban.config/1`. This
  demonstrates fetching the default instance config and querying all jobs:

      Oban
      |> Oban.config()
      |> Oban.Repo.all(Oban.Job)
  """

  @moduledoc since: "2.2.0"

  alias Oban.{Backoff, Config}

  @callbacks_without_opts [
    config: 0,
    default_options: 1,
    get_dynamic_repo: 0,
    in_transaction?: 0,
    load: 2,
    put_dynamic_repo: 1,
    rollback: 1
  ]

  @callbacks_with_opts [
    aggregate: 3,
    all: 2,
    checkout: 2,
    delete!: 2,
    delete: 2,
    delete_all: 2,
    exists?: 2,
    get!: 3,
    get: 3,
    get_by!: 3,
    get_by: 3,
    insert!: 2,
    insert: 2,
    insert_all: 3,
    insert_or_update!: 2,
    insert_or_update: 2,
    one!: 2,
    one: 2,
    preload: 3,
    reload!: 2,
    reload: 2,
    stream: 2,
    update!: 2,
    update: 2,
    update_all: 3
  ]

  @retry_opts delay: 500, retry: 5, expected_delay: 10, expected_retry: 20

  for {fun, arity} <- @callbacks_without_opts do
    args = [Macro.var(:conf, __MODULE__) | Macro.generate_arguments(arity, __MODULE__)]

    @doc """
    Wraps `c:Ecto.Repo.#{fun}/#{arity}` with an additional `Oban.Config` argument.
    """
    def unquote(fun)(unquote_splicing(args)) do
      __dispatch__(unquote(fun), unquote(args))
    end
  end

  for {fun, arity} <- @callbacks_with_opts do
    args = [Macro.var(:conf, __MODULE__) | Macro.generate_arguments(arity - 1, __MODULE__)]

    @doc """
    Wraps `c:Ecto.Repo.#{fun}/#{arity}` with an additional `Oban.Config` argument.
    """
    def unquote(fun)(unquote_splicing(args), opts \\ []) do
      __dispatch__(unquote(fun), unquote(args), opts)
    end
  end

  # Manually Defined

  @doc """
  The default values extracted from `Oban.Config` for use in all queries with options.
  """
  @doc since: "2.14.0"
  def default_options(conf) do
    base = [log: conf.log, oban: true, telemetry_options: [oban_conf: conf]]

    if conf.prefix do
      [prefix: conf.prefix] ++ base
    else
      base
    end
  end

  @doc """
  Wraps `Ecto.Adapters.SQL.Repo.query/4` with an added `Oban.Config` argument.
  """
  @doc since: "2.2.0"
  def query(conf, statement, params \\ [], opts \\ []) do
    __dispatch__(:query, [conf, statement, params], opts)
  end

  @doc """
  Wraps `Ecto.Adapters.SQL.Repo.query!/4` with an added `Oban.Config` argument.
  """
  @doc since: "2.17.0"
  def query!(conf, statement, params \\ [], opts \\ []) do
    __dispatch__(:query!, [conf, statement, params], opts)
  end

  @doc """
  Wraps `Ecto.Adapters.SQL.Repo.to_sql/2` with an added `Oban.Config` argument.
  """
  @doc since: "2.2.0"
  def to_sql(conf, kind, queryable) do
    query =
      queryable
      |> Ecto.Queryable.to_query()
      |> Map.put(:prefix, conf.prefix)

    conf.repo.to_sql(kind, query)
  end

  @doc """
  Wraps `c:Ecto.Repo.transaction/2` with an additional `Oban.Config` argument and automatic
  retries with backoff.

  ## Options

  Backoff helpers, in addition to the standard transaction options:

  * `delay` — the time to sleep between retries, defaults to `500ms`
  * `retry` — the number of retries for unexpected errors, defaults to `5`
  * `expected_delay` — the time to sleep between expected errors, e.g. `serialization` or
    `lock_not_available`, defaults to `10ms`
  * `expected_retry` — the number of retries for expected errors, defaults to `20`
  """
  @doc since: "2.18.1"
  def transaction(conf, fun_or_multi, opts \\ []) do
    transaction(conf, fun_or_multi, opts, 1)
  end

  defp transaction(conf, fun_or_multi, opts, attempt) do
    __dispatch__(:transaction, [conf, fun_or_multi], opts)
  rescue
    error in [DBConnection.ConnectionError, Postgrex.Error, MyXQL.Error] ->
      opts = Keyword.merge(@retry_opts, opts)

      cond do
        expected_error?(error) and attempt < opts[:expected_retry] ->
          jittery_sleep(opts[:expected_delay])

        attempt < opts[:retry] ->
          jittery_sleep(attempt * opts[:delay])

        true ->
          reraise error, __STACKTRACE__
      end

      transaction(conf, fun_or_multi, opts, attempt + 1)
  end

  defp expected_error?(%_{postgres: %{code: :lock_not_available}}), do: true
  defp expected_error?(%_{postgres: %{code: :serialization_failure}}), do: true
  defp expected_error?(_error), do: false

  defp jittery_sleep(delay), do: delay |> Backoff.jitter() |> Process.sleep()

  @doc """
  Executes a function with a dynamic repo using the provided configuration.

  This function allows executing queries with a dynamically chosen repo, which may be determined
  through either a function or a module/function/args tuple. When used within a transaction, the
  dynamic repo is not switched from the current repo.

  ## Examples

      config = Oban.config(Oban)

      Oban.Repo.with_dynamic_repo(config, fn repo ->
        repo.all(Oban.Job)
      end)
  """
  @doc since: "2.20.0"
  def with_dynamic_repo(%{get_dynamic_repo: dyn_fun, repo: repo} = conf, fun)
      when (is_function(dyn_fun, 0) or is_tuple(dyn_fun)) and is_function(fun, 1) do
    prev_repo = repo.get_dynamic_repo()

    dyna_repo =
      case dyn_fun do
        {mod, fun, arg} -> apply(mod, fun, arg)
        fun -> fun.()
      end

    try do
      if not in_transaction?(conf, prev_repo) do
        repo.put_dynamic_repo(dyna_repo)
      end

      fun.(repo)
    after
      repo.put_dynamic_repo(prev_repo)
    end
  end

  def with_dynamic_repo(%{repo: repo}, fun) when is_function(fun, 1) do
    fun.(repo)
  end

  defp __dispatch__(name, [%Config{} = conf | args]) do
    dynamic_dispatch(conf, name, args)
  end

  defp __dispatch__(name, [%Config{} = conf | args], opts) when is_list(opts) do
    opts =
      conf
      |> default_options()
      |> Keyword.merge(opts)

    dynamic_dispatch(conf, name, args ++ [opts])
  end

  defp dynamic_dispatch(conf, name, args) do
    with_dynamic_repo(conf, fn repo -> apply(repo, name, args) end)
  end

  defp in_transaction?(conf, instance) when is_pid(instance), do: conf.repo.in_transaction?()

  defp in_transaction?(conf, instance) when is_atom(instance) do
    case GenServer.whereis(instance) do
      pid when is_pid(pid) -> in_transaction?(conf, pid)
      _ -> false
    end
  end

  defp in_transaction?(_, _), do: false
end
