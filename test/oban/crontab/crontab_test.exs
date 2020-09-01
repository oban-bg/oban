defmodule Oban.Crontab.CronTest do
  use Oban.Case, async: true

  alias Oban.Crontab.Cron

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
        |> Cron.parse!()
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
        assert_raise ArgumentError, fn -> Cron.parse!(expression) end
      end
    end

    test "parsing non-standard expressions" do
      yearly = %Cron{
        minutes: [0],
        hours: [0],
        days: [1],
        months: [1],
        weekdays: [:*]
      }

      assert yearly == Cron.parse!("@yearly")

      assert yearly == Cron.parse!("@annually")

      assert %Cron{
               minutes: [0],
               hours: [0],
               days: [1],
               months: [:*],
               weekdays: [:*]
             } == Cron.parse!("@monthly")

      assert %Cron{
               minutes: [0],
               hours: [0],
               days: [:*],
               months: [:*],
               weekdays: [0]
             } == Cron.parse!("@weekly")

      daily = %Cron{
        minutes: [0],
        hours: [0],
        days: [:*],
        months: [:*],
        weekdays: [:*]
      }

      assert daily == Cron.parse!("@daily")
      assert daily == Cron.parse!("@midnight")

      assert %Cron{
               minutes: [0],
               hours: [:*],
               days: [:*],
               months: [:*],
               weekdays: [:*]
             } == Cron.parse!("@hourly")

      assert %Cron{reboot: true} == Cron.parse!("@reboot")
    end

    test "parsing non-standard weekday ranges" do
      working_days = %Cron{
        minutes: [:*],
        hours: [:*],
        days: [:*],
        months: [:*],
        weekdays: [1, 2, 3, 4, 5]
      }

      assert working_days == Cron.parse!("* * * * MON-FRI")
    end
  end

  describe "now?/2" do
    property "literal values always match the current datetime" do
      check all minute <- integer(1..59),
                hour <- integer(1..23),
                day <- integer(2..28),
                month <- integer(2..12) do
        crontab = %Cron{minutes: [minute], hours: [hour], days: [day], months: [month]}
        datetime = %{DateTime.utc_now() | minute: minute, hour: hour, day: day, month: month}

        assert Cron.now?(crontab, datetime)
        refute Cron.now?(crontab, %{datetime | minute: minute - 1})
        refute Cron.now?(crontab, %{datetime | hour: hour - 1})
        refute Cron.now?(crontab, %{datetime | day: day - 1})
        refute Cron.now?(crontab, %{datetime | month: month - 1})
      end
    end

    test "literal days of the week match the current datetime" do
      sunday_base = DateTime.from_naive!(~N[2020-03-15 22:00:00], "Etc/UTC")

      for day_of_week <- 0..6 do
        crontab = %Cron{weekdays: [day_of_week]}
        datetime = %{sunday_base | day: sunday_base.day + day_of_week}

        assert Cron.now?(crontab, datetime)
      end
    end

    test "reboot never matches" do
      refute Cron.now?(%Cron{reboot: true})
    end
  end

  describe "reboot?/1" do
    test "only reboot matches" do
      assert Cron.reboot?(%Cron{reboot: true})
      refute Cron.reboot?(%Cron{reboot: false})
    end
  end

  defp minutes do
    expression(0..59)
  end

  defp hours do
    expression(0..23)
  end

  defp days do
    expression(1..31)
  end

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
    list_of(one_of([constant(" "), constant("\t")]), min_length: 1, max_length: 4)
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
