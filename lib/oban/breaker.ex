defmodule Oban.Breaker do
  @moduledoc false

  alias Oban.{Config, Telemetry}

  require Logger

  @type state_struct :: %{
          :circuit => :enabled | :disabled,
          :conf => Config.t(),
          :name => GenServer.name(),
          :reset_timer => reference(),
          optional(atom()) => any()
        }

  @max_retries 10
  @min_delay 100
  @default_jitter_mult 0.10
  @default_jitter_mode :both

  defmacro trip_errors, do: [DBConnection.ConnectionError, Postgrex.Error]

  @spec trip_circuit(Exception.t(), Exception.stacktrace(), state_struct()) :: state_struct()
  def trip_circuit(exception, stacktrace, state) do
    meta = %{
      config: state.conf,
      error: exception,
      kind: :error,
      reason: exception,
      message: error_message(exception),
      name: state.name,
      stacktrace: stacktrace
    }

    Telemetry.execute([:oban, :circuit, :trip], %{}, meta)

    if is_reference(state.reset_timer), do: Process.cancel_timer(state.reset_timer)

    reset_timer = Process.send_after(self(), :reset_circuit, state.conf.circuit_backoff)

    %{state | circuit: :disabled, reset_timer: reset_timer}
  end

  @spec open_circuit(state_struct()) :: state_struct()
  def open_circuit(%{circuit: _, name: name, conf: conf} = state) do
    Telemetry.execute([:oban, :circuit, :open], %{}, %{name: name, conf: conf})

    %{state | circuit: :enabled}
  end

  @spec jitter(time :: pos_integer(), opts :: Keyword.t()) :: pos_integer()
  def jitter(time, opts \\ []) do
    mode = Keyword.get(opts, :mode, @default_jitter_mode)
    mult = Keyword.get(opts, :mult, @default_jitter_mult)

    diff = trunc(:rand.uniform() * mult * time)

    case mode do
      :inc ->
        time + diff

      :dec ->
        time - diff

      :both ->
        if :rand.uniform() >= 0.5 do
          time + diff
        else
          time - diff
        end
    end
  end

  @spec with_retry(fun(), integer()) :: term()
  def with_retry(fun, retries \\ 0)

  def with_retry(fun, @max_retries), do: fun.()

  def with_retry(fun, retries) do
    fun.()
  catch
    _kind, _value -> lazy_retry(fun, retries)
  end

  defp lazy_retry(fun, retries) do
    time = @min_delay * :math.pow(2, retries)

    time
    |> trunc()
    |> jitter()
    |> Process.sleep()

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
