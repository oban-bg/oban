defmodule Oban.Backoff do
  @moduledoc false

  @type jitter_mode :: :inc | :dec | :both

  @doc """
  Calculate an exponential backoff in millseconds for a given attempt.

  By default, the exponent is clamped to a maximum of 10 to prevent unreasonably long delays.

  ## Examples

      iex> Oban.Backoff.exponential(1)
      200

      iex> Oban.Backoff.exponential(10)
      102_400

      iex> Oban.Backoff.exponential(11)
      102_400
  """
  @spec exponential(pos_integer(), opts :: keyword()) :: pos_integer()
  def exponential(attempt, opts \\ []) do
    mult_ms = Keyword.get(opts, :mult_ms, 100)
    max_pow = Keyword.get(opts, :max_pow, 10)

    mult_ms * Integer.pow(2, min(attempt, max_pow))
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
  @spec jitter(time :: pos_integer(), [mode: jitter_mode(), mult: float()]) :: pos_integer()
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
  Attempt a function repeatedly until it succeeds or retries are exhausted.

  Failed attempts are spaced out using exponential backoff with jitter. By default, functions are
  tried 10 times over the course of approximately 3 minutes.

  This function is designed to guard against flickering database errors and retry safety only
  applies `DBConnection.ConnectionError` and `Postgrex.Error`.
  """
  @spec with_retry((() -> term()), :infinity | pos_integer()) :: term()
  def with_retry(fun, retries \\ 10) when is_function(fun, 0) and retries > 0 do
    with_retry(fun, retries, 1)
  end

  defp with_retry(fun, retries, attempt) do
    fun.()
  rescue
    error in [DBConnection.ConnectionError, Postgrex.Error] ->
      if retries == :infinity or attempt < retries do
        attempt
        |> exponential()
        |> jitter()
        |> Process.sleep()

        with_retry(fun, retries, attempt + 1)
      else
        reraise error, __STACKTRACE__
      end
  end
end
