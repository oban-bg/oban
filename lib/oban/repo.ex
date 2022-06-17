defmodule Oban.Repo do
  @moduledoc """
  Wrappers around `Ecto.Repo` callbacks.

  These functions should be used when working with an Ecto repo inside a plugin. These functions
  will resolve the correct repo instance, and set the schema prefix and the log level, according
  to the Oban configuration.
  """

  alias Ecto.{Changeset, Multi, Query, Queryable, Schema}
  alias Oban.Config

  @doc "Wraps `c:Ecto.Repo.aggregate/3` and `c:Ecto.Repo.aggregate/4`."
  @spec aggregate(Config.t(), Ecto.Queryable.t(), :count, opts :: Keyword.t()) :: term | nil
  @spec aggregate(
          Config.t(),
          Ecto.Queryable.t(),
          :avg | :count | :max | :min | :sum,
          field :: atom,
          opts :: Keyword.t()
        ) :: term | nil
  @aggregates [:count, :avg, :max, :min, :sum]
  def aggregate(conf, queryable, aggregate, opts \\ [])

  def aggregate(conf, queryable, aggregate, opts)
      when aggregate in [:count] and is_list(opts) do
    with_dynamic_repo(
      conf,
      fn -> conf.repo.aggregate(queryable, aggregate, query_opts(conf, opts)) end
    )
  end

  def aggregate(conf, queryable, aggregate, field)
      when aggregate in @aggregates and is_atom(field) do
    with_dynamic_repo(
      conf,
      fn -> conf.repo.aggregate(queryable, aggregate, field, query_opts(conf, [])) end
    )
  end

  def aggregate(conf, queryable, aggregate, field, opts)
      when aggregate in @aggregates and is_atom(field) and is_list(opts) do
    with_dynamic_repo(
      conf,
      fn -> conf.repo.aggregate(queryable, aggregate, field, query_opts(conf, opts)) end
    )
  end

  @doc "Wraps `c:Ecto.Repo.all/2`."
  @doc since: "2.2.0"
  @spec all(Config.t(), Queryable.t(), Keyword.t()) :: [Schema.t()]
  def all(conf, queryable, opts \\ []) do
    with_dynamic_repo(
      conf,
      fn -> conf.repo.all(queryable, query_opts(conf, opts)) end
    )
  end

  @doc "Wraps `c:Ecto.Repo.checkout/2`."
  @doc since: "2.2.0"
  @spec checkout(Config.t(), (() -> result), Keyword.t()) :: result when result: var
  def checkout(conf, function, opts \\ []) do
    with_dynamic_repo(
      conf,
      fn -> conf.repo.checkout(function, query_opts(conf, opts)) end
    )
  end

  @doc "Wraps `c:Ecto.Repo.config/0`."
  @doc since: "2.2.0"
  @spec config(Config.t()) :: Keyword.t()
  def config(conf), do: with_dynamic_repo(conf, &conf.repo.config/0)

  @doc "Wraps `c:Ecto.Repo.delete/2`."
  @doc since: "2.4.0"
  @spec delete(
          Config.t(),
          struct_or_changeset :: Schema.t() | Changeset.t(),
          opts :: Keyword.t()
        ) :: {:ok, Schema.t()} | {:error, Changeset.t()}
  def delete(conf, struct_or_changeset, opts \\ []) do
    with_dynamic_repo(
      conf,
      fn -> conf.repo.delete(struct_or_changeset, query_opts(conf, opts)) end
    )
  end

  @doc "Wraps `c:Ecto.Repo.delete_all/2`."
  @doc since: "2.2.0"
  @spec delete_all(Config.t(), Queryable.t(), Keyword.t()) :: {integer(), nil | [term()]}
  def delete_all(conf, queryable, opts \\ []) do
    with_dynamic_repo(
      conf,
      fn -> conf.repo.delete_all(queryable, query_opts(conf, opts)) end
    )
  end

  @doc "Wraps `c:Ecto.Repo.insert/2`."
  @doc since: "2.2.0"
  @spec insert(Config.t(), Schema.t() | Changeset.t(), Keyword.t()) ::
          {:ok, Schema.t()} | {:error, Changeset.t()}
  def insert(conf, struct_or_changeset, opts \\ []) do
    with_dynamic_repo(
      conf,
      fn -> conf.repo.insert(struct_or_changeset, query_opts(conf, opts)) end
    )
  end

  @doc "Wraps `c:Ecto.Repo.insert_all/3`."
  @doc since: "2.2.0"
  @spec insert_all(
          Config.t(),
          binary() | {binary(), module()} | module(),
          [map() | [{atom(), term() | Query.t()}]],
          Keyword.t()
        ) :: {integer(), nil | [term()]}
  def insert_all(conf, schema_or_source, entries, opts \\ []) do
    with_dynamic_repo(
      conf,
      fn -> conf.repo.insert_all(schema_or_source, entries, query_opts(conf, opts)) end
    )
  end

  @doc "Wraps `c:Ecto.Repo.one/2`."
  @doc since: "2.2.0"
  @spec one(Config.t(), Queryable.t(), Keyword.t()) :: Schema.t() | nil
  def one(conf, queryable, opts \\ []) do
    with_dynamic_repo(
      conf,
      fn -> conf.repo.one(queryable, query_opts(conf, opts)) end
    )
  end

  @doc "Wraps `Ecto.Adapters.SQL.Repo.query/4`."
  @doc since: "2.2.0"
  @spec query(Config.t(), String.t(), [term()], Keyword.t()) ::
          {:ok,
           %{
             :rows => nil | [[term()] | binary()],
             :num_rows => non_neg_integer(),
             optional(atom()) => any()
           }}
          | {:error, Exception.t()}
  def query(conf, sql, params \\ [], opts \\ []) do
    with_dynamic_repo(conf, fn -> conf.repo.query(sql, params, query_opts(conf, opts)) end)
  end

  @doc "Wraps `c:Ecto.Repo.stream/2`"
  @doc since: "2.9.0"
  @spec stream(Config.t(), Queryable.t(), Keyword.t()) :: Enum.t()
  def stream(conf, queryable, opts \\ []) do
    with_dynamic_repo(conf, fn -> conf.repo.stream(queryable, query_opts(conf, opts)) end)
  end

  @doc "Wraps `c:Ecto.Repo.transaction/2`."
  @doc since: "2.2.0"
  @spec transaction(Config.t(), (... -> any()) | Multi.t(), opts :: Keyword.t()) ::
          {:ok, any()}
          | {:error, any()}
          | {:error, Multi.name(), any(), %{required(Multi.name()) => any()}}
  def transaction(conf, fun_or_multi, opts \\ []) do
    with_dynamic_repo(
      conf,
      fn -> conf.repo.transaction(fun_or_multi, query_opts(conf, opts)) end
    )
  end

  @doc "Wraps `Ecto.Adapters.SQL.Repo.to_sql/2`."
  @doc since: "2.2.0"
  @spec to_sql(Config.t(), :all | :update_all | :delete_all, Queryable.t()) ::
          {String.t(), [term()]}
  def to_sql(conf, kind, queryable) do
    queryable =
      case Map.fetch(conf, :prefix) do
        :error -> queryable
        {:ok, prefix} -> queryable |> Queryable.to_query() |> Map.put(:prefix, prefix)
      end

    conf.repo.to_sql(kind, queryable)
  end

  @doc "Wraps `c:Ecto.Repo.update/2`."
  @doc since: "2.2.0"
  @spec update(Config.t(), Changeset.t(), Keyword.t()) ::
          {:ok, Schema.t()} | {:error, Changeset.t()}
  def update(conf, changeset, opts \\ []) do
    with_dynamic_repo(conf, fn -> conf.repo.update(changeset, query_opts(conf, opts)) end)
  end

  @doc "Wraps `c:Ecto.Repo.update_all/3`."
  @doc since: "2.2.0"
  @spec update_all(Config.t(), Queryable.t(), Keyword.t(), Keyword.t()) ::
          {integer(), nil | [term()]}
  def update_all(conf, queryable, updates, opts \\ []) do
    with_dynamic_repo(
      conf,
      fn -> conf.repo.update_all(queryable, updates, query_opts(conf, opts)) end
    )
  end

  @doc false
  @spec with_dynamic_repo(Config.t(), fun()) :: any()
  def with_dynamic_repo(conf, fun) do
    case get_dynamic_repo(conf) do
      nil ->
        fun.()

      instance ->
        prev_instance = conf.repo.get_dynamic_repo()
        maybe_run_in_transaction(conf, fun, instance, prev_instance)
    end
  end

  defp get_dynamic_repo(%{get_dynamic_repo: fun}) when is_function(fun, 0), do: fun.()
  defp get_dynamic_repo(_conf), do: nil

  defp maybe_run_in_transaction(conf, fun, instance, prev_instance) do
    unless in_transaction?(conf, prev_instance) do
      conf.repo.put_dynamic_repo(instance)
    end

    fun.()
  after
    conf.repo.put_dynamic_repo(prev_instance)
  end

  defp in_transaction?(conf, instance) when is_pid(instance), do: conf.repo.in_transaction?()

  defp in_transaction?(conf, instance) when is_atom(instance) do
    case GenServer.whereis(instance) do
      pid when is_pid(pid) ->
        in_transaction?(conf, pid)

      _ ->
        false
    end
  end

  defp in_transaction?(_, _), do: false

  defp query_opts(conf, opts) do
    opts
    |> Keyword.put(:log, conf.log)
    |> Keyword.put(:prefix, conf.prefix)
    |> Keyword.put(:telemetry_options, oban_conf: conf)
  end
end
