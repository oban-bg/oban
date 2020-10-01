defmodule Oban.Repo do
  def transaction(conf, fun_or_multi, opts \\ []) do
    conf.repo.transaction(fun_or_multi, with_default_opts(opts, conf))
  end

  def update(conf, changeset, opts \\ []) do
    with_dynamic_repo(
      conf,
      fn -> conf.repo.update(changeset, query_opts(opts, conf)) end
    )
  end

  def update_all(conf, queryable, updates, opts \\ []) do
    with_dynamic_repo(
      conf,
      fn -> conf.repo.update_all(queryable, updates, query_opts(opts, conf)) end
    )
  end

  def query(conf, sql, params \\ [], opts \\ []) do
    with_dynamic_repo(
      conf,
      fn -> conf.repo.query(sql, params, query_opts(opts, conf)) end
    )
  end

  def all(conf, queryable, opts \\ []) do
    with_dynamic_repo(
      conf,
      fn -> conf.repo.all(queryable, query_opts(opts, conf)) end
    )
  end

  def one(conf, queryable, opts \\ []) do
    with_dynamic_repo(
      conf,
      fn -> conf.repo.one(queryable, query_opts(opts, conf)) end
    )
  end

  def insert(conf, struct_or_changeset, opts \\ []) do
    with_dynamic_repo(
      conf,
      fn -> conf.repo.insert(struct_or_changeset, query_opts(opts, conf)) end
    )
  end

  def insert_all(conf, schema_or_source, entries, opts \\ []) do
    with_dynamic_repo(
      conf,
      fn -> conf.repo.insert_all(schema_or_source, entries, query_opts(opts, conf)) end
    )
  end

  def delete_all(conf, queryable, opts \\ []) do
    with_dynamic_repo(
      conf,
      fn -> conf.repo.delete_all(queryable, query_opts(opts, conf)) end
    )
  end

  def checkout(conf, function, opts \\ []) do
    with_dynamic_repo(
      conf,
      fn -> conf.repo.checkout(function, query_opts(opts, conf)) end
    )
  end

  def to_sql(conf, kind, queryable) do
    queryable =
      case Map.fetch(conf, :prefix) do
        :error -> queryable
        {:ok, prefix} -> queryable |> Ecto.Queryable.to_query() |> Map.put(:prefix, prefix)
      end

    conf.repo.to_sql(kind, queryable)
  end

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
