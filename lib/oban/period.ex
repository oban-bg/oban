defmodule Oban.Period do
  @moduledoc """
  Periods represent durations of time as either raw seconds or a unit tuple.

  All periods are normalized to seconds internally. The tuple format provides a more expressive
  way to specify durations in larger units:

      # Raw seconds
      60

      # Unit tuple
      {1, :minute}
      {5, :minutes}
      {2, :hours}

  Supported time units are `:second`, `:seconds`, `:minute`, `:minutes`, `:hour`, `:hours`,
  `:day`, `:days`, `:week`, and `:weeks`.
  """
  @moduledoc since: "2.20.0"

  @typedoc """
  Supported time units for period tuples.

  Both singular and plural forms are accepted, e.g. `:minute` and `:minutes`.
  """
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

  @typedoc """
  A time duration as seconds or a unit tuple.
  """
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

  @doc """
  Checks whether the given value is a non-negative integer suitable for seconds.
  """
  defguard is_seconds(seconds) when is_integer(seconds) and seconds >= 0

  @doc """
  Checks whether the given value is a valid period, either seconds or a unit tuple.
  """
  defguard is_valid_period(period)
           when is_seconds(period) or
                  (is_tuple(period) and tuple_size(period) == 2 and
                     is_integer(elem(period, 0)) and elem(period, 0) >= 0 and
                     elem(period, 1) in @time_units)

  @doc """
  Convert a period to seconds.

  ## Examples

      iex> Oban.Period.to_seconds(60)
      60

      iex> Oban.Period.to_seconds({1, :minute})
      60

      iex> Oban.Period.to_seconds({2, :hours})
      7200
  """
  @spec to_seconds(t()) :: pos_integer()
  def to_seconds({value, unit}) when unit in ~w(second seconds)a, do: value
  def to_seconds({value, unit}) when unit in ~w(minute minutes)a, do: value * 60
  def to_seconds({value, unit}) when unit in ~w(hour hours)a, do: value * 60 * 60
  def to_seconds({value, unit}) when unit in ~w(day days)a, do: value * 24 * 60 * 60
  def to_seconds({value, unit}) when unit in ~w(week weeks)a, do: value * 24 * 60 * 60 * 7
  def to_seconds(seconds) when is_seconds(seconds), do: seconds

  @doc """
  Convert a period to milliseconds.

  Unlike `to_seconds/1`, a bare integer is considered milliseconds and returned unchanged; only
  unit tuples are expanded.

  ## Examples

      iex> Oban.Period.to_milliseconds(1000)
      1000

      iex> Oban.Period.to_milliseconds({1, :second})
      1000

      iex> Oban.Period.to_milliseconds({2, :minutes})
      120_000
  """
  @spec to_milliseconds(t()) :: pos_integer()
  def to_milliseconds({_value, _unit} = period), do: to_seconds(period) * 1000
  def to_milliseconds(milliseconds) when is_seconds(milliseconds), do: milliseconds
end
