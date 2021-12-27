defmodule Oban.Backoff do
  @moduledoc false

  @max_retries 10
  @min_delay 100
  @default_jitter_mult 0.10
  @default_jitter_mode :both

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
end
