defmodule Oban.Plugins.Reindexer do
  @moduledoc """
  Deprecated, use `Oban.Reindexer` instead.
  """

  @doc false
  @deprecated "Use Oban.Reindexer instead"
  defdelegate child_spec(opts), to: Oban.Reindexer

  @doc false
  @deprecated "Use Oban.Reindexer instead"
  defdelegate start_link(opts), to: Oban.Reindexer

  @doc false
  @deprecated "Use Oban.Reindexer instead"
  defdelegate init(state), to: Oban.Reindexer

  @doc false
  @deprecated "Use Oban.Reindexer instead"
  defdelegate validate(opts), to: Oban.Reindexer
end
