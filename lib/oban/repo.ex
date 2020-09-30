defmodule Oban.Repo do
  def transaction(conf, fun_or_multi, opts \\ []) do
    conf.repo.transaction(fun_or_multi, Keyword.merge(default_opts(conf), opts))
  end

  def update_all(conf, queryable, updates, opts \\ []) do
    opts =
      default_opts(conf)
      |> Keyword.merge(opts)
      |> Keyword.merge(prefix: conf.prefix)

    conf.repo.update_all(queryable, updates, opts)
  end

  defp default_opts(conf) do
    [log: conf.log]
  end
end
