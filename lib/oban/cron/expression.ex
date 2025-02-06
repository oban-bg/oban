defmodule Oban.Cron.Expression do
  @moduledoc false

  @type t :: %__MODULE__{
          input: String.t(),
          minutes: MapSet.t(),
          hours: MapSet.t(),
          days: MapSet.t(),
          months: MapSet.t(),
          weekdays: MapSet.t(),
          reboot?: boolean()
        }

  @derive {Inspect, only: [:input]}
  defstruct [:input, :minutes, :hours, :days, :months, :weekdays, reboot?: false]

  @dow_map %{
    "SUN" => "0",
    "MON" => "1",
    "TUE" => "2",
    "WED" => "3",
    "THU" => "4",
    "FRI" => "5",
    "SAT" => "6"
  }

  @mon_map %{
    "JAN" => "1",
    "FEB" => "2",
    "MAR" => "3",
    "APR" => "4",
    "MAY" => "5",
    "JUN" => "6",
    "JUL" => "7",
    "AUG" => "8",
    "SEP" => "9",
    "OCT" => "10",
    "NOV" => "11",
    "DEC" => "12"
  }

  @min_range 0..59
  @hrs_range 0..23
  @day_range 1..31
  @mon_range 1..12
  @dow_range 0..6

  @doc """
  Check whether a cron expression matches the current date and time.

  ## Example

  Check against the default `utc_now`:

      iex> "* * * * *" |> parse!() |> now?()
      true

  Check against a provided date time:

      iex> "0 1 * * *" |> parse!() |> now?(~U[2025-01-01 01:00:00Z])
      true

      iex> "0 1 * * *" |> parse!() |> now?(~U[2025-01-01 02:00:00Z])
      false

  Check if it is time to reboot:

      iex> "@reboot" |> parse!() |> now?()
      true
  """
  @spec now?(cron :: t(), datetime :: DateTime.t()) :: boolean()
  def now?(cron, datetime \\ DateTime.utc_now())

  def now?(%__MODULE__{reboot?: true}, _datetime), do: true

  def now?(%__MODULE__{} = cron, datetime) do
    dow = day_of_week(datetime)

    MapSet.member?(cron.months, datetime.month) and
      MapSet.member?(cron.weekdays, dow) and
      MapSet.member?(cron.days, datetime.day) and
      MapSet.member?(cron.hours, datetime.hour) and
      MapSet.member?(cron.minutes, datetime.minute)
  end

  @doc """
  Returns the next DateTime that matches the cron expression.

  When given a DateTime, it finds the next matching time after that DateTime. When given
  a timezone string, it finds the next matching time in that timezone.

  ## Examples

  Find the next matching time after a given DateTime:

      iex> "0 1 * * *" |> parse!() |> next_at(~U[2025-01-01 00:00:00Z])
      ~U[2025-01-01 01:00:00Z]

  Find the next matching time in a specific timezone:

      iex> "0 1 * * *" |> parse!() |> next_at("America/New_York")
      ~U[2025-01-02 01:00:00-05:00]
  """
  @spec next_at(t(), DateTime.t() | Calendar.time_zone()) :: :unknown | DateTime.t()
  def next_at(expr, timezone \\ "Etc/UTC")

  def next_at(%{reboot?: true}, _timezone_or_datetime), do: :unknown

  def next_at(expr, timezone) when is_binary(timezone) do
    next_at(expr, DateTime.now!(timezone))
  end

  def next_at(expr, time) when is_struct(time, DateTime) do
    time =
      time
      |> DateTime.add(1, :minute)
      |> DateTime.truncate(:second)
      |> Map.put(:second, 0)

    match_at(expr, time, :next)
  end

  defp match_at(expr, time, dir) do
    cond do
      now?(expr, time) ->
        time

      not MapSet.member?(expr.months, time.month) ->
        match_at(expr, bump_month(expr, time, dir), dir)

      not MapSet.member?(expr.days, time.day) ->
        match_at(expr, bump_day(expr, time, dir), dir)

      not MapSet.member?(expr.hours, time.hour) ->
        match_at(expr, bump_hour(expr, time, dir), dir)

      true ->
        match_at(expr, bump_minute(expr, time, dir), dir)
    end
  end

  defp bump_year(_expr, time, :next) do
    %{time | month: 0, year: time.year + 1}
  end

  defp bump_year(_expr, time, :last) do
    %{time | month: 13, year: time.year - 1}
  end

  defp bump_month(expr, time, dir) do
    day = if dir == :next, do: 0, else: 32

    case find_best(expr.months, time.month, dir) do
      nil -> bump_year(expr, time, dir)
      month -> %{time | day: day, month: month}
    end
  end

  defp bump_day(expr, time, dir) do
    hour = if dir == :next, do: -1, else: 24
    days = days_in_month(time)

    matches_weekday? = fn day ->
      day <= days and
        %{time | day: day}
        |> day_of_week()
        |> then(&(&1 in expr.weekdays))
    end

    expr.days
    |> Enum.filter(matches_weekday?)
    |> find_best(time.day, dir)
    |> case do
      nil -> bump_month(expr, time, dir)
      day -> %{time | day: day, hour: hour}
    end
  end

  defp bump_hour(expr, time, dir) do
    minute = if dir == :next, do: -1, else: 60

    case find_best(expr.hours, time.hour, dir) do
      nil -> bump_day(expr, time, dir)
      hour -> %{time | hour: hour, minute: minute}
    end
  end

  defp bump_minute(expr, time, dir) do
    case find_best(expr.minutes, time.minute, dir) do
      nil -> bump_hour(expr, time, dir)
      minute -> %{time | minute: minute}
    end
  end

  defp find_best(set, value, :next) do
    set
    |> Enum.sort()
    |> Enum.find(&(&1 > value))
  end

  defp find_best(set, value, :last) do
    set
    |> Enum.sort(:desc)
    |> Enum.find(&(&1 < value))
  end

  @doc """
  Returns the most recent DateTime that matches the cron expression.

  When given a DateTime, it finds the last matching time before that DateTime. When given
  a timezone string, it finds the last matching time in that timezone.

  ## Examples

  Find the last matching time before a given DateTime:

      iex> "0 1 * * *" |> parse!() |> last_at(~U[2025-01-01 01:00:00Z])
      ~U[2025-01-01 00:01:00Z]

  Find the last matching time in a specific timezone:

      iex> "0 1 * * *" |> parse!() |> last_at("America/New_York")
      ~U[2025-01-01 05:01:00-05:00]
  """
  @spec last_at(t(), DateTime.t() | Calendar.time_zone()) :: DateTime.t()
  def last_at(expr, timezone \\ "Etc/UTC")

  def last_at(%{reboot?: true}, _timezone_or_datetime) do
    {uptime, _} = :erlang.statistics(:wall_clock)

    DateTime.utc_now()
    |> DateTime.add(-uptime, :millisecond)
    |> DateTime.truncate(:second)
    |> Map.put(:second, 0)
  end

  def last_at(expr, timezone) when is_binary(timezone) do
    last_at(expr, DateTime.now!(timezone))
  end

  def last_at(expr, time) when is_struct(time, DateTime) do
    time =
      time
      |> DateTime.add(-1, :minute)
      |> DateTime.truncate(:second)
      |> Map.put(:second, 0)

    match_at(expr, time, :last)
  end

  defp day_of_week(datetime) do
    if Calendar.ISO.valid_date?(datetime.year, datetime.month, datetime.day) do
      datetime
      |> Date.day_of_week()
      |> Integer.mod(7)
    else
      -1
    end
  end

  defp days_in_month(datetime) do
    Calendar.ISO.days_in_month(datetime.year, datetime.month)
  end

  @spec parse(input :: binary()) :: {:ok, t()} | {:error, Exception.t()}
  def parse("@annually"), do: parse("0 0 1 1 *")
  def parse("@yearly"), do: parse("0 0 1 1 *")
  def parse("@monthly"), do: parse("0 0 1 * *")
  def parse("@weekly"), do: parse("0 0 * * 0")
  def parse("@midnight"), do: parse("0 0 * * *")
  def parse("@daily"), do: parse("0 0 * * *")
  def parse("@hourly"), do: parse("0 * * * *")
  def parse("@reboot"), do: {:ok, %__MODULE__{input: "@reboot", reboot?: true}}

  def parse(input) when is_binary(input) do
    case String.split(input, ~r/\s+/, trim: true, parts: 5) do
      [mip, hrp, dap, mop, wdp] ->
        {:ok,
         %__MODULE__{
           input: input,
           minutes: parse_field(mip, @min_range),
           hours: parse_field(hrp, @hrs_range),
           days: parse_field(dap, @day_range),
           months: mop |> trans_field(@mon_map) |> parse_field(@mon_range),
           weekdays: wdp |> trans_field(@dow_map) |> parse_field(@dow_range)
         }}

      _parts ->
        throw({:error, "incorrect number of fields in expression: #{input}"})
    end
  catch
    {:error, message} -> {:error, %ArgumentError{message: message}}
  end

  @spec parse!(input :: binary()) :: t()
  def parse!(input) when is_binary(input) do
    case parse(input) do
      {:ok, cron} -> cron
      {:error, exception} -> raise(exception)
    end
  end

  defp parse_field(field, range) do
    range_set = MapSet.new(range)

    parsed =
      field
      |> String.split(~r/\s*,\s*/)
      |> Enum.flat_map(&parse_part(&1, range))
      |> MapSet.new()

    if not MapSet.subset?(parsed, range_set) do
      throw({:error, "expression field #{field} is out of range: #{inspect(range)}"})
    end

    parsed
  end

  defp trans_field(field, map) do
    Enum.reduce(map, field, fn {val, rep}, acc -> String.replace(acc, val, rep) end)
  end

  defp parse_part(part, range) do
    cond do
      part == "*" ->
        range

      part =~ ~r/^\d+$/ ->
        parse_literal(part)

      part =~ ~r/^\*\/[1-9]\d?$/ ->
        parse_step(part, range)

      part =~ ~r/^\d+(\-\d+)?\/[1-9]\d?$/ ->
        parse_range_step(part, range)

      part =~ ~r/^\d+\-\d+$/ ->
        parse_range(part, range)

      true ->
        throw({:error, "unrecognized cron expression: #{part}"})
    end
  end

  defp parse_literal(part) do
    part
    |> String.to_integer()
    |> List.wrap()
  end

  defp parse_step(part, range) do
    step =
      part
      |> String.replace_leading("*/", "")
      |> String.to_integer()

    Enum.take_every(range, step)
  end

  defp parse_range_step(part, max_range) do
    [range, step] = String.split(part, "/")

    parse_step(step, parse_range(range, max_range))
  end

  defp parse_range(part, max_range) do
    case String.split(part, "-") do
      [rall] ->
        String.to_integer(rall)..Enum.max(max_range)

      [rmin, rmax] ->
        rmin = String.to_integer(rmin)
        rmax = String.to_integer(rmax)

        if rmin <= rmax do
          rmin..rmax
        else
          throw(
            {:error,
             "left side (#{rmin}) of a range must be less than or equal to the right side (#{rmax})"}
          )
        end
    end
  end
end
