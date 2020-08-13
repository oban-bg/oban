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
