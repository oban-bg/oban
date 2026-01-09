defmodule Oban.Period do
  @moduledoc false

  @type time_unit ::
          :second
          | :seconds
          | :minute
          | :minutes
          | :hour
          | :hours
          | :day
          | :days
          | :week
          | :weeks

  @type t :: pos_integer() | {pos_integer(), time_unit()}

  @time_units ~w(
    second
    seconds
    minute
    minutes
    hour
    hours
    day
    days
    week
    weeks
  )a

  defguard is_seconds(seconds) when is_integer(seconds) and seconds >= 0

  defguard is_valid_period(period)
           when is_seconds(period) or
                  (is_tuple(period) and tuple_size(period) == 2 and
                     is_integer(elem(period, 0)) and elem(period, 0) >= 0 and
                     elem(period, 1) in @time_units)

  @spec to_seconds(t()) :: pos_integer()
  def to_seconds({value, unit}) when unit in ~w(second seconds)a, do: value
  def to_seconds({value, unit}) when unit in ~w(minute minutes)a, do: value * 60
  def to_seconds({value, unit}) when unit in ~w(hour hours)a, do: value * 60 * 60
  def to_seconds({value, unit}) when unit in ~w(day days)a, do: value * 24 * 60 * 60
  def to_seconds({value, unit}) when unit in ~w(week weeks)a, do: value * 24 * 60 * 60 * 7
  def to_seconds(seconds) when is_seconds(seconds), do: seconds
end
