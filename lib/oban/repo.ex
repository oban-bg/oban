defmodule Oban.Repo do
  def transaction(conf, fun_or_multi, opts \\ []) do
    conf.repo.transaction(fun_or_multi, with_default_opts(opts, conf))
  end

  def update(conf, changeset, opts \\ []),
    do: conf.repo.update(changeset, query_opts(opts, conf))

  def update_all(conf, queryable, updates, opts \\ []),
    do: conf.repo.update_all(queryable, updates, query_opts(opts, conf))

  def query(conf, sql, params \\ [], opts \\ []),
    do: conf.repo.query(sql, params, query_opts(opts, conf))

  def all(conf, queryable, opts \\ []),
    do: conf.repo.all(queryable, query_opts(opts, conf))

  def insert(conf, struct_or_changeset, opts \\ []),
    do: conf.repo.insert(struct_or_changeset, query_opts(opts, conf))

  def insert_all(conf, schema_or_source, entries, opts \\ []),
    do: conf.repo.insert_all(schema_or_source, entries, query_opts(opts, conf))

  def checkout(conf, function, opts \\ []),
    do: conf.repo.checkout(function, query_opts(opts, conf))

  defp query_opts(opts, conf) do
    opts
    |> with_default_opts(conf)
    |> Keyword.merge(conf |> Map.take([:prefix]) |> Map.to_list())
  end

  defp with_default_opts(opts, conf),
    do: Keyword.merge(opts, conf |> Map.take([:log]) |> Map.to_list())
end
