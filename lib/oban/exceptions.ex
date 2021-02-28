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

defmodule Oban.PerformError do
  @moduledoc """
  Wraps the reason returned by `{:error, reason}`, `{:discard, reason}` in a proper exception.

  The original return tuple is available in the `:reason` key.
  """

  alias Oban.Worker

  defexception [:message, :reason]

  @impl Exception
  def exception({worker, reason}) do
    message = "#{Worker.to_string(worker)} failed with #{inspect(reason)}"

    %__MODULE__{message: message, reason: reason}
  end
end

defmodule Oban.TimeoutError do
  @moduledoc """
  Returned when a job is terminated early due to a custom timeout.
  """

  alias Oban.Worker

  defexception [:message, :reason]

  @impl Exception
  def exception({worker, timeout}) do
    message = "#{Worker.to_string(worker)} timed out after #{timeout}ms"

    %__MODULE__{message: message, reason: :timeout}
  end
end
