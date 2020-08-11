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
