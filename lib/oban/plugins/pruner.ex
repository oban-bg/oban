defmodule Oban.Plugins.Pruner do
  @moduledoc """
  Deprecated, use `Oban.Pruner` instead.
  """

  @doc false
  @deprecated "Use Oban.Pruner instead"
  defdelegate child_spec(opts), to: Oban.Pruner

  @doc false
  @deprecated "Use Oban.Pruner instead"
  defdelegate start_link(opts), to: Oban.Pruner

  @doc false
  @deprecated "Use Oban.Pruner instead"
  defdelegate init(state), to: Oban.Pruner

  @doc false
  @deprecated "Use Oban.Pruner instead"
  defdelegate validate(opts), to: Oban.Pruner
end
