defmodule Oban.BreakerTest do
  use Oban.Case, async: true
  use ExUnitProperties

  alias Oban.Breaker

  property "jitter creates time deviations within interval" do
    check all mode <- one_of([:add, :dec, :both]),
              mult <- float(min: 0),
              time <- positive_integer() do
      result = Breaker.jitter(time, mult: mult, mode: mode)
      max_diff = trunc(time * mult)

      assert result <= time + max_diff
      assert result >= time - max_diff
    end
  end
end
