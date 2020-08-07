defmodule Oban.CrashError do
  @moduledoc """
  Wraps unhandled exits and throws that occur during job execution.
  """

  defexception [:message]

  @impl Exception
  def exception({kind, reason, stacktrace}) do
    %__MODULE__{message: Exception.format_banner(kind, reason, stacktrace)}
  end
end
