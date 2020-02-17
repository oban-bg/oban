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

  @max_retries 10
  @min_delay 100
  @jitter_mult 0.10

  defmacro trip_errors, do: [DBConnection.ConnectionError, Postgrex.Error]

  @spec trip_circuit(Exception.t(), list(), state_struct()) :: state_struct()
  def trip_circuit(exception, stack, %{circuit: _, conf: conf, name: name} = state) do
    :telemetry.execute(
      [:oban, :trip_circuit],
      %{},
      %{error: exception, message: error_message(exception), name: name, stack: stack}
    )

    Process.send_after(self(), :reset_circuit, conf.circuit_backoff)

    %{state | circuit: :disabled}
  end

  @spec open_circuit(state_struct()) :: state_struct()
  def open_circuit(%{circuit: _, name: name} = state) do
    :telemetry.execute([:oban, :open_circuit], %{}, %{name: name})

    %{state | circuit: :enabled}
  end

  @spec with_retry(fun(), integer()) :: term()
  def with_retry(fun, retries \\ 0)

  def with_retry(fun, @max_retries), do: fun.()

  def with_retry(fun, retries) do
    fun.()
  rescue
    _exception -> lazy_retry(fun, retries)
  catch
    _kind, _value -> lazy_retry(fun, retries)
  end

  defp lazy_retry(fun, retries) do
    base = @min_delay * :math.pow(2, retries)
    diff = base * @jitter_mult
    sleep = Enum.random(trunc(base - diff)..trunc(base + diff))

    Process.sleep(sleep)

    with_retry(fun, retries + 1)
  end

  defp error_message(%Postgrex.Error{} = exception) do
    Postgrex.Error.message(exception)
  end

  defp error_message(%DBConnection.ConnectionError{} = exception) do
    DBConnection.ConnectionError.message(exception)
  end

  defp error_message(exception), do: inspect(exception)
end
