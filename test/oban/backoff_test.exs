defmodule Oban.BackoffTest do
  use Oban.Case, async: true

  doctest Oban.Backoff

  alias Oban.Backoff

  property "exponential backoff is clamped within a fixed range" do
    maximum = 2 ** 10 * 10

    check all multiplier <- integer(1..10),
              attempt <- integer(1..20) do
      result = Backoff.exponential(attempt, mult_ms: multiplier)

      assert result >= 2
      assert result <= maximum
    end
  end

  property "jitter creates time deviations within interval" do
    check all mode <- one_of([:inc, :dec, :both]),
              mult <- float(min: 0),
              time <- positive_integer() do
      result = Backoff.jitter(time, mult: mult, mode: mode)
      max_diff = trunc(time * mult)

      assert result <= time + max_diff
      assert result >= time - max_diff
    end
  end
end
