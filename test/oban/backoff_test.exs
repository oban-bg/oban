defmodule Oban.BackoffTest do
  use Oban.Case, async: true

  use ExUnitProperties

  doctest Oban.Backoff

  alias Oban.Backoff

  describe "exponential/2" do
    property "exponential backoff is clamped within a fixed range" do
      maximum = Integer.pow(2, 10) * 10

      check all mult <- integer(1..10),
                attempt <- integer(1..20) do
        result = Backoff.exponential(attempt, mult: mult)

        assert result >= 2
        assert result <= maximum
      end
    end
  end

  describe "jitter/2" do
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

  describe "with_retry/2" do
    test "retrying known database connection errors" do
      fun = fn -> raise DBConnection.ConnectionError end

      assert_raise DBConnection.ConnectionError, fn ->
        fun
        |> fail_first()
        |> Backoff.with_retry(1)
      end

      assert :ok =
               fun
               |> fail_first()
               |> Backoff.with_retry(2)
    end

    test "retrying caught timeout exits" do
      fun = fn -> exit({:timeout, {GenServer, :call, []}}) end

      assert fun
             |> fail_first()
             |> Backoff.with_retry(1)
             |> catch_exit()

      assert :ok =
               fun
               |> fail_first()
               |> Backoff.with_retry(2)
    end

    test "reraising unknown exceptions and exits" do
      assert_raise RuntimeError, fn ->
        Backoff.with_retry(fn -> raise RuntimeError end, 3)
      end

      assert catch_exit(Backoff.with_retry(fn -> exit(:normal) end, 3))
    end
  end

  defp fail_first(return_fun) do
    ref = :counters.new(1, [])

    fn ->
      :counters.add(ref, 1, 1)

      case :counters.get(ref, 1) do
        1 -> return_fun.()
        _ -> :ok
      end
    end
  end
end
