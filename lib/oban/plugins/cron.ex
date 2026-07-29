defmodule Oban.Plugins.Cron do
  @moduledoc """
  Deprecated, use `Oban.Cron` instead.
  """

  @doc false
  @deprecated "Use Oban.Cron instead"
  defdelegate child_spec(opts), to: Oban.Cron

  @doc false
  @deprecated "Use Oban.Cron instead"
  defdelegate start_link(opts), to: Oban.Cron

  @doc false
  @deprecated "Use Oban.Cron instead"
  defdelegate init(state), to: Oban.Cron

  @doc false
  @deprecated "Use Oban.Cron instead"
  defdelegate validate(opts), to: Oban.Cron

  @doc false
  @deprecated "Use Oban.Cron instead"
  defdelegate parse(input), to: Oban.Cron

  @doc false
  @deprecated "Use Oban.Cron instead"
  defdelegate interval_to_next_minute(), to: Oban.Cron
end
