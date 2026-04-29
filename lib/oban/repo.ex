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

  ## Retries

  Every dispatch through `Oban.Repo` is wrapped in a bounded retry loop that tolerates transient
  failures without surfacing them to callers:

  * `DBConnection.ConnectionError`, `Postgrex.Error`, and `MyXQL.Error` raised from inside a
    transaction are retried with backoff. Expected conflicts like serialization failures,
    deadlocks, and lock-not-available use a shorter delay and higher retry count than unexpected
    errors.

  * `UndefinedFunctionError` raised by the configured repo module is retried for all operations.
    This absorbs the window during which the repo module is unavailable, e.g. mid-recompile in a
    slow dev environment, so periodic plugins and stagers don't crash on a compile blip.

  Defaults for both loops are set at compile time and keyed on `Oban.Repo`:

      config :oban, Oban.Repo,
        retry_opts: [
          delay: 500,
          retry: 5,
          expected_delay: 10,
          expected_retry: 20
        ]

  Changes require recompiling `:oban`. See `transaction/3` for the meaning of each option and for
  per-call overrides.
  """

  @moduledoc since: "2.2.0"

  alias Oban.{Backoff, Config}

  require Oban.Errors

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

  @retry_opts Application.compile_env(:oban, [__MODULE__, :retry_opts],
                delay: 500,
                retry: 5,
                expected_delay: 10,
                expected_retry: 20
              )

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

  Unexpected errors such as `DBConnection.ConnectionError`, `Postgrex.Error`, or `MyXQL.Error`
  will retry with a delay scaled by attempt number. Expected conflicts (serialization failures,
  deadlocks, and lock-not-available) retry with a shorter delay and higher attempt budget, since
  they typically resolve quickly once contention clears.

  ## Options

  In addition to the standard `c:Ecto.Repo.transaction/2` options:

  * `:delay` — milliseconds to sleep between unexpected-error retries, scaled by attempt and
    jittered. Defaults to `500`.
  * `:retry` — maximum attempts for unexpected errors. Defaults to `5`. Pass `0` or `false` to
    disable retries entirely, including for expected conflicts.
  * `:expected_delay` — milliseconds to sleep between expected-conflict retries, jittered.
    Defaults to `10`.
  * `:expected_retry` — maximum attempts for expected conflicts. Defaults to `20`.

  Defaults are drawn from the compile-time `:retry_opts` configuration documented on the module.
  Any option passed here overrides the compile-time default for this call.

  > #### Nested Transactions {: .warning}
  >
  > When calling `transaction/3` inside an existing transaction, e.g. invoking > `Oban.insert/2`
  > from within your application's own `Repo.transaction/2` block, pass `retry: false` to disable
  > retries. A retry after a deadlock or serialization failure inside a savepoint will mask the
  > real error from the outer transaction and leave you debugging a phantom timeout instead of
  > the underlying conflict.
  """
  @doc since: "2.18.1"
  def transaction(conf, fun_or_multi, opts \\ []) do
    transaction(conf, fun_or_multi, opts, 1)
  end

  defp transaction(conf, fun_or_multi, opts, attempt) do
    __dispatch__(:transaction, [conf, fun_or_multi], opts)
  rescue
    error in Oban.Errors.database_errors() ->
      opts = Keyword.merge(@retry_opts, opts)

      cond do
        opts[:retry] in [0, false] ->
          reraise error, __STACKTRACE__

        expected_error?(error) and attempt < opts[:expected_retry] ->
          jittery_sleep(opts[:expected_delay])

        attempt < opts[:retry] ->
          jittery_sleep(attempt * opts[:delay])

        true ->
          reraise error, __STACKTRACE__
      end

      transaction(conf, fun_or_multi, opts, attempt + 1)
  end

  defp expected_error?(%_{postgres: %{code: :deadlock_detected}}), do: true
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
    dynamic_dispatch(conf, name, args, 1)
  end

  defp dynamic_dispatch(conf, name, args, attempt) do
    with_dynamic_repo(conf, fn repo -> apply(repo, name, args) end)
  rescue
    error in UndefinedFunctionError ->
      cond do
        not repo_unavailable?(conf, error) ->
          reraise error, __STACKTRACE__

        attempt < @retry_opts[:retry] ->
          jittery_sleep(attempt * @retry_opts[:delay])
          dynamic_dispatch(conf, name, args, attempt + 1)

        true ->
          reraise error, __STACKTRACE__
      end
  end

  defp repo_unavailable?(%Config{repo: repo}, %UndefinedFunctionError{module: repo}), do: true
  defp repo_unavailable?(_conf, _error), do: false

  defp in_transaction?(conf, instance) when is_pid(instance), do: conf.repo.in_transaction?()

  defp in_transaction?(conf, instance) when is_atom(instance) do
    case GenServer.whereis(instance) do
      pid when is_pid(pid) -> in_transaction?(conf, pid)
      _ -> false
    end
  end

  defp in_transaction?(_, _), do: false
end
