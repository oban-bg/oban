defmodule Oban.CronTest do
  use ExUnit.Case, async: true

  use ExUnitProperties

  alias Oban.Cron

  describe "interval_to_next_minute/1" do
    property "calculated time is always within a short future range" do
      check all hour <- integer(0..23),
                minute <- integer(0..59),
                second <- integer(0..59),
                max_runs: 1_000 do
        {:ok, time} = Time.new(hour, minute, second)

        assert Cron.interval_to_next_minute(time) in 1_000..60_000
      end
    end
  end
end
