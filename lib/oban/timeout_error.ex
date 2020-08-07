defmodule Oban.TimeoutError do
  @moduledoc """
  Returned when a job is terminated early due to a custom timeout.
  """

  alias Oban.Worker

  defexception [:message]

  @impl Exception
  def exception({worker, timeout}) do
    %__MODULE__{message: "#{Worker.to_string(worker)} timed out after #{timeout}ms"}
  end
end
