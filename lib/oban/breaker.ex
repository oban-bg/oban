defmodule Oban.Breaker do
  @moduledoc false

  require Logger

  alias Oban.Config

  @type state_struct :: %{
          :circuit => :enabled | :disabled,
          :conf => Config.t(),
          :name => GenServer.name(),
          optional(atom()) => any()
        }

  defmacro trip_errors, do: [DBConnection.ConnectionError, Postgrex.Error]

  @spec trip_circuit(Exception.t(), state_struct()) :: state_struct()
  def trip_circuit(exception, %{circuit: _, conf: conf, name: name} = state) do
    :telemetry.execute(
      [:oban, :trip_circuit],
      %{},
      %{message: error_message(exception), name: name}
    )

    Process.send_after(self(), :reset_circuit, conf.circuit_backoff)

    %{state | circuit: :disabled}
  end

  @spec open_circuit(state_struct()) :: state_struct()
  def open_circuit(%{circuit: _, name: name} = state) do
    :telemetry.execute([:oban, :open_circuit], %{}, %{name: name})

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
