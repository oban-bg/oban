defmodule Oban.Backoff do
  @moduledoc false

  @default_jitter_mode :both
  @default_jitter_mult 0.10
  @min_delay 100

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

  @spec with_retry((() -> term()), pos_integer()) :: term()
  def with_retry(fun, retries \\ 10) when is_function(fun, 0) and retries > 0 do
    with_retry(fun, retries, 1)
  end

  defp with_retry(fun, retries, attempt) do
    fun.()
  rescue
    error in [DBConnection.ConnectionError, Postgrex.Error] ->
      if attempt < retries do
        (@min_delay * :math.pow(2, attempt))
        |> trunc()
        |> jitter()
        |> Process.sleep()

        with_retry(fun, retries, attempt + 1)
      else
        reraise error, __STACKTRACE__
      end
  end
end
