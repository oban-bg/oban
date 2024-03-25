defmodule Oban.Backoff do
  @moduledoc false

  @type jitter_mode :: :inc | :dec | :both

  @retry_mult Application.compile_env(:oban, [Oban.Backoff, :retry_mult], 100)

  @doc """
  Calculate an exponential backoff in seconds for a given attempt.

  By default, the exponent is clamped to a maximum of 10 to prevent unreasonably long delays.

  ## Examples

      iex> Oban.Backoff.exponential(1)
      2

      iex> Oban.Backoff.exponential(1, mult: 100)
      200

      iex> Oban.Backoff.exponential(1, min_pad: 10)
      12

      iex> Oban.Backoff.exponential(10)
      1024

      iex> Oban.Backoff.exponential(11)
      1024
  """
  @spec exponential(pos_integer(), opts :: keyword()) :: number()
  def exponential(attempt, opts \\ []) do
    max_pow = Keyword.get(opts, :max_pow, 10)
    min_pad = Keyword.get(opts, :min_pad, 0)
    mult = Keyword.get(opts, :mult, 1)

    min_pad + mult * Integer.pow(2, min(attempt, max_pow))
  end

  @doc """
  Applies a random amount of jitter to the provided value.

  ## Examples

      iex> jitter = Oban.Backoff.jitter(200)
      ...> jitter in 180..220
      true

      iex> jitter = Oban.Backoff.jitter(200, mode: :inc)
      ...> jitter in 200..220
      true

      iex> jitter = Oban.Backoff.jitter(200, mode: :dec)
      ...> jitter in 180..200
      true
  """
  @spec jitter(time :: pos_integer(), mode: jitter_mode(), mult: float()) :: number()
  def jitter(time, opts \\ []) do
    mode = Keyword.get(opts, :mode, :both)
    mult = Keyword.get(opts, :mult, 0.1)
    rand = :rand.uniform()

    diff = trunc(rand * mult * time)

    case mode do
      :inc ->
        time + diff

      :dec ->
        time - diff

      :both ->
        if rand >= 0.5 do
          time + diff
        else
          time - diff
        end
    end
  end

  @doc """
  Attempt a database interraction repeatedly until it succeeds or retries are exhausted.

  Failed attempts are spaced out using exponential backoff with jitter. By default, functions are
  retried _infinitely_ with a maximum of ~100 seconds between retries.

  This function is designed to guard against flickering database errors and retry safety only
  applies `DBConnection.ConnectionError`, `Postgrex.Error`, and `GenServer` timeouts.

  ## Examples

      iex> Oban.Backoff.with_retry(fn -> :ok end)
      :ok

      iex> Oban.Backoff.with_retry(fn -> :ok end, :infinity)
      :ok

      iex> Oban.Backoff.with_retry(fn -> :ok end, 10)
      :ok
  """
  @spec with_retry((-> term()), :infinity | pos_integer()) :: term()
  def with_retry(fun, retries \\ :infinity) when is_function(fun, 0) do
    with_retry(fun, retries, 1)
  end

  @db_errors [DBConnection.ConnectionError, Postgrex.Error]

  defp with_retry(fun, retries, attempt) do
    fun.()
  rescue
    error in @db_errors ->
      retry_or_raise(fun, retries, attempt, :error, error, __STACKTRACE__)
  catch
    :exit, {error, _} = reason when error in [:timeout | @db_errors] ->
      retry_or_raise(fun, retries, attempt, :exit, reason, __STACKTRACE__)
  end

  @compile {:inline, retry_or_raise: 6}

  defp retry_or_raise(fun, retries, attempt, kind, reason, stacktrace) do
    if retries == :infinity or attempt < retries do
      attempt
      |> exponential(mult: @retry_mult)
      |> jitter()
      |> Process.sleep()

      with_retry(fun, retries, attempt + 1)
    else
      :erlang.raise(kind, reason, stacktrace)
    end
  end
end
