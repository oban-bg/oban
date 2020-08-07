defmodule Oban.PerformError do
  @moduledoc """
  Wraps the reason returned by `{:error, reason}`, `{:discard, reason}` in a proper exception.
  """

  alias Oban.Worker

  defexception [:message]

  @impl Exception
  def exception({worker, reason}) do
    %__MODULE__{message: "#{Worker.to_string(worker)} failed with #{inspect(reason)}"}
  end
end
