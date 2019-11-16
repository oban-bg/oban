defmodule Oban.Breaker do
  @moduledoc false

  require Logger

  alias Oban.Config

  @type state_struct :: %{
          :circuit => :enabled | :disabled,
          :conf => Config.t(),
          optional(atom()) => any()
        }

  @trip_errors [DBConnection.ConnectionError, Postgrex.Error]

  defmacro trip_errors, do: @trip_errors

  @spec trip_circuit(Exception.t(), state_struct()) :: map()
  def trip_circuit(exception, %{circuit: _, conf: conf} = state) do
    Logger.error(fn ->
      Jason.encode!(%{
        source: "oban",
        message: "Circuit temporarily tripped",
        error: error_message(exception)
      })
    end)

    Process.send_after(self(), :reset_circuit, conf.circuit_backoff)

    %{state | circuit: :disabled}
  end

  @spec open_circuit(state_struct()) :: map()
  def open_circuit(%{circuit: _} = state) do
    %{state | circuit: :enabled}
  end

  defp error_message(%Postgrex.Error{} = exception) do
    Postgrex.Error.message(exception)
  end

  defp error_message(%DBConnection.ConnectionError{} = exception) do
    DBConnection.ConnectionError.message(exception)
  end

  defp error_message(exception), do: inspect(exception)
end
