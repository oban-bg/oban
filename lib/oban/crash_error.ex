defmodule Oban.CrashError do
  @moduledoc """
  Wraps unhandled exits and throws that occur during job execution.
  """

  defexception [:message, :reason]

  @impl Exception
  def exception({kind, reason, stacktrace}) do
    message = Exception.format_banner(kind, reason, stacktrace)

    %__MODULE__{message: message, reason: reason}
  end
end
