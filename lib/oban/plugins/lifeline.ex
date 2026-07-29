defmodule Oban.Plugins.Lifeline do
  @moduledoc """
  Deprecated, use `Oban.Lifeline` instead.
  """

  @doc false
  @deprecated "Use Oban.Lifeline instead"
  defdelegate child_spec(opts), to: Oban.Lifeline

  @doc false
  @deprecated "Use Oban.Lifeline instead"
  defdelegate start_link(opts), to: Oban.Lifeline

  @doc false
  @deprecated "Use Oban.Lifeline instead"
  defdelegate init(state), to: Oban.Lifeline

  @doc false
  @deprecated "Use Oban.Lifeline instead"
  defdelegate validate(opts), to: Oban.Lifeline
end
