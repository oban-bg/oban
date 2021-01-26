defmodule Oban.Repo do
  @moduledoc """
  Wrappers around `Ecto.Repo` callbacks.

  These functions should be used when working with an Ecto repo inside a plugin. These functions
  will resolve the correct repo instance, and set the schema prefix and the log level, according
  to the Oban configuration.
  """

  @type config :: %{
          :repo => module,
          optional(:get_dynamic_repo) => (() -> pid | atom),
          optional(:log) => false | Logger.level(),
          optional(:prefix) => binary(),
          optional(any) => any
        }

  @doc "Wraps `c:Ecto.Repo.transaction/2`."
  @doc since: "2.2.0"
  @spec transaction(config(), (... -> any()) | Ecto.Multi.t(), opts :: Keyword.t()) ::
          {:ok, any()}
          | {:error, any()}
          | {:error, Ecto.Multi.name(), any(), %{required(Ecto.Multi.name()) => any()}}
  def transaction(conf, fun_or_multi, opts \\ []) do
    with_dynamic_repo(
      conf,
      fn -> conf.repo.transaction(fun_or_multi, with_default_opts(opts, conf)) end
    )
  end

  @doc "Wraps `c:Ecto.Repo.update/2`."
  @doc since: "2.2.0"
  @spec update(config(), Ecto.Changeset.t(), Keyword.t()) ::
          {:ok, Ecto.Schema.t()} | {:error, Ecto.Changeset.t()}
  def update(conf, changeset, opts \\ []) do
    with_dynamic_repo(
      conf,
      fn -> conf.repo.update(changeset, query_opts(opts, conf)) end
    )
  end

  @doc "Wraps `c:Ecto.Repo.update_all/3`."
  @doc since: "2.2.0"
  @spec update_all(config(), Ecto.Queryable.t(), Keyword.t(), Keyword.t()) ::
          {integer(), nil | [term()]}
  def update_all(conf, queryable, updates, opts \\ []) do
    with_dynamic_repo(
      conf,
      fn -> conf.repo.update_all(queryable, updates, query_opts(opts, conf)) end
    )
  end

  @doc "Wraps `Ecto.Adapters.SQL.Repo.query/4`."
  @doc since: "2.2.0"
  @spec query(config(), String.t(), [term()], Keyword.t()) ::
          {:ok,
           %{
             :rows => nil | [[term()] | binary()],
             :num_rows => non_neg_integer(),
             optional(atom()) => any()
           }}
          | {:error, Exception.t()}
  def query(conf, sql, params \\ [], opts \\ []) do
    with_dynamic_repo(
      conf,
      fn -> conf.repo.query(sql, params, query_opts(opts, conf)) end
    )
  end

  @doc "Wraps `c:Ecto.Repo.all/2`."
  @doc since: "2.2.0"
  @spec all(config(), Ecto.Queryable.t(), Keyword.t()) :: [Ecto.Schema.t()]
  def all(conf, queryable, opts \\ []) do
    with_dynamic_repo(
      conf,
      fn -> conf.repo.all(queryable, query_opts(opts, conf)) end
    )
  end

  @doc "Wraps `c:Ecto.Repo.one/2`."
  @doc since: "2.2.0"
  @spec one(config(), Ecto.Queryable.t(), Keyword.t()) :: Ecto.Schema.t() | nil
  def one(conf, queryable, opts \\ []) do
    with_dynamic_repo(
      conf,
      fn -> conf.repo.one(queryable, query_opts(opts, conf)) end
    )
  end

  @doc "Wraps `c:Ecto.Repo.delete/2`."
  @doc since: "2.4.0"
  @spec delete(
          config(),
          struct_or_changeset :: Ecto.Schema.t() | Ecto.Changeset.t(),
          opts :: Keyword.t()
        ) :: {:ok, Ecto.Schema.t()} | {:error, Ecto.Changeset.t()}
  def delete(conf, struct_or_changeset, opts \\ []) do
    with_dynamic_repo(
      conf,
      fn -> conf.repo.delete(struct_or_changeset, query_opts(opts, conf)) end
    )
  end

  @doc "Wraps `c:Ecto.Repo.insert/2`."
  @doc since: "2.2.0"
  @spec insert(config(), Ecto.Schema.t() | Ecto.Changeset.t(), Keyword.t()) ::
          {:ok, Ecto.Schema.t()} | {:error, Ecto.Changeset.t()}
  def insert(conf, struct_or_changeset, opts \\ []) do
    with_dynamic_repo(
      conf,
      fn -> conf.repo.insert(struct_or_changeset, query_opts(opts, conf)) end
    )
  end

  @doc "Wraps `c:Ecto.Repo.insert_all/3`."
  @doc since: "2.2.0"
  @spec insert_all(
          config(),
          binary() | {binary(), module()} | module(),
          [map() | [{atom(), term() | Ecto.Query.t()}]],
          Keyword.t()
        ) :: {integer(), nil | [term()]}
  def insert_all(conf, schema_or_source, entries, opts \\ []) do
    with_dynamic_repo(
      conf,
      fn -> conf.repo.insert_all(schema_or_source, entries, query_opts(opts, conf)) end
    )
  end

  @doc "Wraps `c:Ecto.Repo.delete_all/2`."
  @doc since: "2.2.0"
  @spec delete_all(config(), Ecto.Queryable.t(), Keyword.t()) :: {integer(), nil | [term()]}
  def delete_all(conf, queryable, opts \\ []) do
    with_dynamic_repo(
      conf,
      fn -> conf.repo.delete_all(queryable, query_opts(opts, conf)) end
    )
  end

  @doc "Wraps `c:Ecto.Repo.checkout/2`."
  @doc since: "2.2.0"
  @spec checkout(config(), (() -> result), Keyword.t()) :: result when result: var
  def checkout(conf, function, opts \\ []) do
    with_dynamic_repo(
      conf,
      fn -> conf.repo.checkout(function, query_opts(opts, conf)) end
    )
  end

  @doc "Wraps `Ecto.Adapters.SQL.Repo.to_sql/2`."
  @doc since: "2.2.0"
  @spec to_sql(config(), :all | :update_all | :delete_all, Ecto.Queryable.t()) ::
          {String.t(), [term()]}
  def to_sql(conf, kind, queryable) do
    queryable =
      case Map.fetch(conf, :prefix) do
        :error -> queryable
        {:ok, prefix} -> queryable |> Ecto.Queryable.to_query() |> Map.put(:prefix, prefix)
      end

    conf.repo.to_sql(kind, queryable)
  end

  @doc "Wraps `c:Ecto.Repo.config/0`."
  @doc since: "2.2.0"
  @spec config(config()) :: Keyword.t()
  def config(conf), do: with_dynamic_repo(conf, &conf.repo.config/0)

  defp with_dynamic_repo(conf, fun) do
    case get_dynamic_repo(conf) do
      nil ->
        fun.()

      instance ->
        prev_instance = conf.repo.get_dynamic_repo()

        try do
          conf.repo.put_dynamic_repo(instance)
          fun.()
        after
          conf.repo.put_dynamic_repo(prev_instance)
        end
    end
  end

  defp get_dynamic_repo(%{get_dynamic_repo: fun}) when is_function(fun, 0), do: fun.()
  defp get_dynamic_repo(_conf), do: nil

  defp query_opts(opts, conf) do
    opts
    |> with_default_opts(conf)
    |> Keyword.merge(conf |> Map.take([:prefix]) |> Map.to_list())
  end

  defp with_default_opts(opts, conf),
    do: Keyword.merge(opts, conf |> Map.take([:log]) |> Map.to_list())
end
