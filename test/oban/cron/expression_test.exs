defmodule Oban.Cron.ExpressionTest do
  use Oban.Case, async: true

  use ExUnitProperties

  alias Oban.Cron.Expression, as: Expr

  describe "parse/1" do
    test "parsing expressions without raising an exception" do
      assert {:ok, _} = Expr.parse("* * * * *")
      assert {:error, %ArgumentError{}} = Expr.parse("* * * *")
    end
  end

  describe "parse!/1" do
    property "expressions with literals, wildcards, ranges, steps and lists are parsed" do
      check all minutes <- minutes(),
                hours <- hours(),
                days <- days(),
                months <- months(),
                weekdays <- weekdays(),
                spaces <- spaces() do
        spacing = IO.iodata_to_binary(spaces)

        [minutes, hours, days, months, weekdays]
        |> Enum.join(spacing)
        |> Expr.parse!()
      end
    end

    test "step ranges are calculated from the lower value of the range" do
      assert MapSet.new([0, 12]) == Expr.parse!("* 0/12 * * *").hours
      assert MapSet.new([1, 8, 15, 22]) == Expr.parse!("* 1/7 * * *").hours
      assert MapSet.new([1, 8]) == Expr.parse!("* 1-14/7 * * *").hours
    end

    test "parsing expressions that are out of bounds fails" do
      expressions = [
        "* * * *",
        "60 * * * *",
        "* 24 * * *",
        "* * 32 * *",
        "* * * 13 *",
        "* * * * 7",
        "*/0 * * * *",
        "ONE * * * *",
        "* * * jan *",
        "* * * * sun"
      ]

      for expression <- expressions do
        assert_raise ArgumentError, fn -> Expr.parse!(expression) end
      end
    end
  end

  describe "now?/2" do
    property "literal values always match the current datetime" do
      check all minute <- integer(1..59),
                hour <- integer(1..23),
                day <- integer(2..28),
                month <- integer(2..12) do
        cron =
          [minute, hour, day, month, "*"]
          |> Enum.join(" ")
          |> Expr.parse!()

        datetime = %{DateTime.utc_now() | minute: minute, hour: hour, day: day, month: month}

        assert Expr.now?(cron, datetime)
        refute Expr.now?(cron, %{datetime | minute: minute - 1})
        refute Expr.now?(cron, %{datetime | hour: hour - 1})
        refute Expr.now?(cron, %{datetime | day: day - 1})
        refute Expr.now?(cron, %{datetime | month: month - 1})
      end
    end

    test "the @reboot special expression evaluates to now" do
      assert "@reboot" |> Expr.parse!() |> Expr.now?()
    end

    test "literal days of the week match the current datetime" do
      sunday_base = DateTime.from_naive!(~N[2020-03-15 22:00:00], "Etc/UTC")

      for day_of_week <- 0..6 do
        datetime = %{sunday_base | day: sunday_base.day + day_of_week}

        assert ("* * * * " <> to_string(day_of_week))
               |> Expr.parse!()
               |> Expr.now?(datetime)
      end
    end
  end

  describe "last_at/2" do
    defp last_at(expr, time) do
      expr
      |> Expr.parse!()
      |> Expr.last_at(time)
    end

    test "returning the system start time for @reboot" do
      time = DateTime.utc_now()
      last = last_at("@reboot", time)

      assert DateTime.after?(time, last)
    end

    test "calculating the last time a cron matched" do
      assert ~U[2024-11-21 00:54:00Z] == last_at("* * * * *", ~U[2024-11-21 00:55:00Z])
      assert ~U[2024-11-21 00:54:00Z] == last_at("*/2 * * * *", ~U[2024-11-21 00:55:00Z])
      assert ~U[2024-11-21 00:05:00Z] == last_at("5 * * * *", ~U[2024-11-21 00:06:00Z])
      assert ~U[2024-11-21 01:00:00Z] == last_at("0 1 * * *", ~U[2024-11-21 01:02:00Z])
      assert ~U[2024-11-21 02:00:00Z] == last_at("0 */2 * * *", ~U[2024-11-21 03:02:00Z])
      assert ~U[2024-11-01 00:00:00Z] == last_at("0 0 1 * *", ~U[2024-11-21 01:01:00Z])
      assert ~U[2024-09-05 02:00:00Z] == last_at("0 0-2 5 9 *", ~U[2024-11-21 01:01:00Z])
      assert ~U[2023-09-05 02:00:00Z] == last_at("0 0-2 5 9 *", ~U[2024-09-04 00:00:00Z])
      assert ~U[2022-09-05 01:00:00Z] == last_at("0 1 5 9 MON", ~U[2024-11-21 00:00:00Z])
    end

    property "the last_at time is always in the past" do
      check all minutes <- minutes(),
                hours <- hours(),
                days <- days(),
                months <- months() do
        assert [minutes, hours, days, months, "*"]
               |> Enum.join(" ")
               |> last_at("Etc/UTC")
               |> DateTime.before?(DateTime.utc_now())
      end
    end
  end

  describe "next_at/2" do
    defp next_at(expr, time) do
      expr
      |> Expr.parse!()
      |> Expr.next_at(time)
    end

    test "the next run for @reboot is unknown" do
      assert :unknown == next_at("@reboot", "Etc/UTC")
    end

    test "calculating the next time a cron will match" do
      assert ~U[2024-11-21 00:56:00Z] == next_at("* * * * *", ~U[2024-11-21 00:55:00Z])
      assert ~U[2024-11-21 00:56:00Z] == next_at("*/2 * * * *", ~U[2024-11-21 00:55:00Z])
      assert ~U[2024-11-21 01:05:00Z] == next_at("5 * * * *", ~U[2024-11-21 00:06:00Z])
      assert ~U[2024-11-21 13:00:00Z] == next_at("0 13 * * *", ~U[2024-11-21 01:02:00Z])
      assert ~U[2024-11-21 04:00:00Z] == next_at("0 */2 * * *", ~U[2024-11-21 03:02:00Z])
      assert ~U[2024-12-01 00:00:00Z] == next_at("0 0 1 * *", ~U[2024-11-21 01:01:00Z])
      assert ~U[2025-09-05 00:00:00Z] == next_at("0 0-2 5 9 *", ~U[2024-11-21 01:01:00Z])
      assert ~U[2024-09-05 00:00:00Z] == next_at("0 0-2 5 9 *", ~U[2024-09-04 00:00:00Z])
      assert ~U[2027-09-05 01:00:00Z] == next_at("0 1 5 9 SUN", ~U[2024-11-21 00:00:00Z])
    end

    property "the next_at time is always in the future" do
      check all minutes <- minutes(),
                hours <- hours(),
                days <- days(),
                months <- months() do
        assert [minutes, hours, days, months, "*"]
               |> Enum.join(" ")
               |> next_at("Etc/UTC")
               |> DateTime.after?(DateTime.utc_now())
      end
    end
  end

  defp minutes, do: expression(0..59)

  defp hours, do: expression(0..23)

  defp days, do: expression(1..28)

  defp months do
    one_of([
      expression(1..12),
      constant("JAN"),
      constant("FEB"),
      constant("MAR"),
      constant("APR"),
      constant("MAY"),
      constant("JUN"),
      constant("JUL"),
      constant("AUG"),
      constant("SEP"),
      constant("OCT"),
      constant("NOV"),
      constant("DEC")
    ])
  end

  defp weekdays do
    one_of([
      expression(0..6),
      constant("MON"),
      constant("TUE"),
      constant("WED"),
      constant("THU"),
      constant("FRI"),
      constant("SAT"),
      constant("SUN")
    ])
  end

  defp spaces do
    list_of(one_of([constant(" "), constant("\t")]), min_length: 1)
  end

  defp expression(min..max//_) do
    gen all expr <-
              one_of([
                constant("*"),
                integer(min..max),
                map(integer(min..max), &"#{&1}/2"),
                map(integer((min + 1)..max), &"*/#{&1}"),
                map(integer(min..(max - 2)), &"#{&1}-#{&1 + 1}"),
                map(integer(min..(max - 3)), &"#{&1}-#{&1 + 2}/2"),
                list_of(integer(min..max), length: 1..10)
              ]) do
      expr
      |> List.wrap()
      |> Enum.join(",")
    end
  end
end
