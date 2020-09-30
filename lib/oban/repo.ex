defmodule Oban.Repo do
  def transaction(conf, fun_or_multi, opts \\ []) do
    conf.repo.transaction(fun_or_multi, Keyword.merge(default_opts(conf), opts))
  end

  defp default_opts(conf) do
    [log: conf.log]
  end
end
