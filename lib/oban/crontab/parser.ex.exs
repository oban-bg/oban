defmodule Oban.Crontab.Parser do
  @moduledoc false

  # parsec:Oban.Crontab.Parser

  import NimbleParsec

  month_alias =
    [
      replace(string("JAN"), 1),
      replace(string("FEB"), 2),
      replace(string("MAR"), 3),
      replace(string("APR"), 4),
      replace(string("MAY"), 5),
      replace(string("JUN"), 6),
      replace(string("JUL"), 7),
      replace(string("AUG"), 8),
      replace(string("SEP"), 9),
      replace(string("OCT"), 10),
      replace(string("NOV"), 11),
      replace(string("DEC"), 12)
    ]
    |> choice()
    |> unwrap_and_tag(:literal)

  weekday_alias =
    [
      replace(string("MON"), 1),
      replace(string("TUE"), 2),
      replace(string("WED"), 3),
      replace(string("THU"), 4),
      replace(string("FRI"), 5),
      replace(string("SAT"), 6),
      replace(string("SUN"), 0)
    ]
    |> choice()
    |> unwrap_and_tag(:literal)

  range =
    integer(min: 1, max: 2)
    |> ignore(string("-"))
    |> integer(min: 1, max: 2)
    |> tag(:range)

  step =
    string("*/")
    |> ignore()
    |> integer(min: 1, max: 2)
    |> unwrap_and_tag(:step)

  literal = integer(min: 1, max: 2) |> unwrap_and_tag(:literal)

  wild = string("*") |> unwrap_and_tag(:wild)

  separator = string(",") |> ignore()

  expression = choice([range, literal, step, wild, separator])

  minutes =
    expression
    |> times(min: 1)
    |> tag(:minutes)

  hours =
    expression
    |> times(min: 1)
    |> tag(:hours)

  days =
    expression
    |> times(min: 1)
    |> tag(:days)

  months =
    [month_alias, expression]
    |> choice()
    |> times(min: 1)
    |> tag(:months)

  weekdays =
    [weekday_alias, expression]
    |> choice()
    |> times(min: 1)
    |> tag(:weekdays)

  whitespace = ascii_string([?\s, ?\t], min: 1)

  defparsec(
    :cron,
    minutes
    |> ignore(whitespace)
    |> concat(hours)
    |> ignore(whitespace)
    |> concat(days)
    |> ignore(whitespace)
    |> concat(months)
    |> ignore(whitespace)
    |> concat(weekdays)
  )

  # parsec:Oban.Crontab.Parser
end
