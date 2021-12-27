defmodule Oban.BackoffTest do
  use Oban.Case, async: true
  use ExUnitProperties

  alias Oban.Backoff

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
