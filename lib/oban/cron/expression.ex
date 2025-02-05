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

  @spec now?(cron :: t(), datetime :: DateTime.t()) :: boolean()
  def now?(cron, datetime \\ DateTime.utc_now())

  def now?(%__MODULE__{reboot?: true}, _datetime), do: true

  def now?(%__MODULE__{} = cron, datetime) do
    cron
    |> Map.from_struct()
    |> Enum.all?(&included?(&1, datetime))
  end

  defp included?({:minutes, set}, datetime), do: MapSet.member?(set, datetime.minute)
  defp included?({:hours, set}, datetime), do: MapSet.member?(set, datetime.hour)
  defp included?({:days, set}, datetime), do: MapSet.member?(set, datetime.day)
  defp included?({:months, set}, datetime), do: MapSet.member?(set, datetime.month)
  defp included?({:weekdays, set}, datetime), do: MapSet.member?(set, day_of_week(datetime))
  defp included?(_field, _datetime), do: true

  defp day_of_week(datetime) do
    if days_in_month(datetime) <= datetime.day do
      datetime
      |> Date.day_of_week()
      |> Integer.mod(7)
    else
      0
    end
  end

  @spec last_at(t(), DateTime.t() | Calendar.timezone()) :: DateTime.t()
  def last_at(expr, timezone \\ "Etc/UTC")

  def last_at(%{reboot?: true}, _timezone_or_datetime) do
    {ms, _} = :erlang.statistics(:wall_clock)

    DateTime.utc_now()
    |> DateTime.add(-ms, :millisecond)
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

    vals =
      expr
      |> Map.from_struct()
      |> Map.drop([:input, :reboot?])
      |> Map.new(fn {key, val} -> {key, Enum.sort(val, :desc)} end)

    Process.put(:recur, 0)

    last_match_at(expr, vals, time)
  end

  defp last_match_at(expr, vals, time) when is_struct(time, DateTime) do
    case Process.get(:recur) do
      val when val > 10 -> raise RuntimeError, inspect({expr, time})
      val -> Process.put(:recur, val + 1)
    end

    IO.inspect(time)

    cond do
      now?(expr, time) ->
        time

      not MapSet.member?(expr.months, time.month) ->
        last_match_at(expr, vals, prev_month(vals, time))

      not MapSet.member?(expr.days, time.day) ->
        last_match_at(expr, vals, prev_day(vals, time))

      not MapSet.member?(expr.hours, time.hour) ->
        last_match_at(expr, vals, prev_hour(vals, time))

      true ->
        last_match_at(expr, vals, prev_minute(vals, time))
    end
  end

  defp prev_month(vals, time) do
    case Enum.find(vals.months, &(&1 <= time.month)) do
      nil ->
        %{time | day: 31, month: 12, year: time.year - 1}

      month ->
        day = days_in_month(%{time | month: month})

        %{time | day: day, month: month}
    end
  end

  defp prev_day(vals, time) do
    days_in_month = days_in_month(time)

    matches_weekday? = fn day ->
      day <= days_in_month and
        time.year
        |> Date.new!(time.month, day)
        |> Date.day_of_week()
        |> then(&(&1 in vals.weekdays))
    end

    case Enum.find(vals.days, &(matches_weekday?.(&1) and &1 <= time.day)) do
      nil -> prev_month(vals, time)
      day -> %{time | day: day, hour: 23}
    end
  end

  defp prev_hour(vals, time) do
    case Enum.find(vals.hours, &(&1 <= time.hour)) do
      nil -> prev_day(vals, time)
      hour -> %{time | hour: hour, minute: 59}
    end
  end

  defp prev_minute(vals, time) do
    case Enum.find(vals.minutes, &(&1 < time.minute)) do
      nil -> prev_hour(vals, time)
      minute -> %{time | minute: minute}
    end
  end

  defp days_in_month(time) do
    time
    |> DateTime.to_date()
    |> Date.days_in_month()
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
