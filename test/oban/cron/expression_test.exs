defmodule Oban.Cron.ExpressionTest do
  use Oban.Case, async: true

  alias Oban.Cron.Expression, as: Expr

  describe "parse!/1" do
    property "expressions with literals, wildcards, ranges, steps and lists are parsed" do
      check all minutes <- minutes(),
                hours <- hours(),
                days <- days(),
                months <- months(),
                weekdays <- weekdays(),
                spaces <- spaces() do
        spacing = :erlang.iolist_to_binary(spaces)

        [minutes, hours, days, months, weekdays]
        |> Enum.join(spacing)
        |> Expr.parse!()
      end
    end

    test "parsing expressions that are out of bounds fails" do
      expressions = [
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

    test "parsing non-standard expressions" do
      assert Expr.parse!("0 0 1 1 *") == Expr.parse!("@annually")
      assert Expr.parse!("0 0 1 1 *") == Expr.parse!("@yearly")
      assert Expr.parse!("0 0 1 * *") == Expr.parse!("@monthly")
      assert Expr.parse!("0 0 * * 0") == Expr.parse!("@weekly")
      assert Expr.parse!("0 0 * * *") == Expr.parse!("@midnight")
      assert Expr.parse!("0 0 * * *") == Expr.parse!("@daily")
      assert Expr.parse!("0 * * * *") == Expr.parse!("@hourly")
    end

    test "parsing non-standard weekday ranges" do
      assert MapSet.new([1, 2]) == Expr.parse!("* * * * MON-TUE").weekdays
      assert MapSet.new([1, 2, 3, 4, 5]) == Expr.parse!("* * * * MON-FRI").weekdays
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

    test "the @reboot special expression initially evaluates to now" do
      cron = Expr.parse!("@reboot")

      assert Expr.now?(cron)
      refute Expr.now?(cron, DateTime.add(DateTime.utc_now(), -60, :second))
      refute Expr.now?(cron, DateTime.add(DateTime.utc_now(), 60, :second))
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

  defp minutes, do: expression(0..59)

  defp hours, do: expression(0..23)

  defp days, do: expression(1..31)

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

  defp expression(min..max) do
    gen all expr <-
              one_of([
                constant("*"),
                integer(min..max),
                map(integer((min + 1)..max), &"*/#{&1}"),
                map(integer(min..(max - 2)), &"#{&1}-#{&1 + 1}"),
                map(integer(min..(max - 3)), &"#{&1}-#{&1 + 2}/1"),
                map(integer(min..(max - 3)), &"#{&1}-#{&1 + 2}/2"),
                list_of(integer(min..max), length: 1..10)
              ]) do
      expr
      |> List.wrap()
      |> Enum.join(",")
    end
  end
end
