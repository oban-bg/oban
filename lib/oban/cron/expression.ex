defmodule Oban.Cron.Expression do
  @moduledoc false

  @type t :: %__MODULE__{
          minutes: MapSet.t(),
          hours: MapSet.t(),
          days: MapSet.t(),
          months: MapSet.t(),
          weekdays: MapSet.t()
        }

  defstruct [:minutes, :hours, :days, :months, :weekdays]

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

  @doc """
  Evaluate whether a cron struct overlaps with the current date time.
  """
  @spec now?(cron :: t(), datetime :: DateTime.t()) :: boolean()
  def now?(%__MODULE__{} = cron, datetime \\ DateTime.utc_now()) do
    cron
    |> Map.from_struct()
    |> Enum.all?(&included?(&1, datetime))
  end

  defp included?({_, :*}, _datetime), do: true
  defp included?({:minutes, set}, datetime), do: MapSet.member?(set, datetime.minute)
  defp included?({:hours, set}, datetime), do: MapSet.member?(set, datetime.hour)
  defp included?({:days, set}, datetime), do: MapSet.member?(set, datetime.day)
  defp included?({:months, set}, datetime), do: MapSet.member?(set, datetime.month)
  defp included?({:weekdays, set}, datetime), do: MapSet.member?(set, day_of_week(datetime))

  defp day_of_week(datetime) do
    datetime
    |> Date.day_of_week()
    |> Integer.mod(7)
  end

  @doc """
  Parses a crontab expression into a %Cron{} struct.

  The parser can handle common expressions that use minutes, hours, days, months and weekdays,
  along with ranges and steps. It also supports common extensions, also called nicknames.

  Raises an `ArgumentError` if the expression cannot be parsed.

  ## Nicknames

  - @yearly: Run once a year, "0 0 1 1 *".
  - @annually: same as @yearly
  - @monthly: Run once a month, "0 0 1 * *".
  - @weekly: Run once a week, "0 0 * * 0".
  - @daily: Run once a day, "0 0 * * *".
  - @midnight: same as @daily
  - @hourly: Run once an hour, "0 * * * *".
  - @reboot: Run once at boot

  ## Examples

      iex> parse!("@hourly")
      %Cron{}

      iex> parse!("0 * * * *")
      %Cron{}

      iex> parse!("60 * * * *")
      ** (ArgumentError)
  """
  @spec parse!(input :: binary()) :: t()
  def parse!("@annually"), do: parse!("0 0 1 1 *")
  def parse!("@yearly"), do: parse!("0 0 1 1 *")
  def parse!("@monthly"), do: parse!("0 0 1 * *")
  def parse!("@weekly"), do: parse!("0 0 * * 0")
  def parse!("@midnight"), do: parse!("0 0 * * *")
  def parse!("@daily"), do: parse!("0 0 * * *")
  def parse!("@hourly"), do: parse!("0 * * * *")

  def parse!("@reboot") do
    now = DateTime.utc_now()

    [now.minute, now.hour, now.day, now.month, day_of_week(now)]
    |> Enum.join(" ")
    |> parse!()
  end

  def parse!(input) when is_binary(input) do
    [mip, hrp, dap, mop, wdp] =
      input
      |> String.trim()
      |> String.split(~r/\s+/, parts: 5)

    %__MODULE__{
      minutes: parse_field(mip, 0..59),
      hours: parse_field(hrp, 0..23),
      days: parse_field(dap, 1..31),
      months: mop |> trans_field(@mon_map) |> parse_field(1..12),
      weekdays: wdp |> trans_field(@dow_map) |> parse_field(0..6)
    }
  end

  defp parse_field(field, range) do
    range_set = MapSet.new(range)

    parsed =
      field
      |> String.split(~r/\s*,\s*/)
      |> Enum.flat_map(&parse_part(&1, range))
      |> MapSet.new()

    unless MapSet.subset?(parsed, range_set) do
      raise ArgumentError, "expression field #{field} is out of range #{inspect(range)}"
    end

    parsed
  end

  defp trans_field(field, map) do
    Enum.reduce(map, field, fn {val, rep}, acc -> String.replace(acc, val, rep) end)
  end

  defp parse_part(part, range) do
    cond do
      part == "*" -> range
      part =~ ~r/^\d+$/ -> parse_literal(part)
      part =~ ~r/^\*\/[1-9]\d?$/ -> parse_step(part, range)
      part =~ ~r/^\d+\-\d+\/[1-9]\d?$/ -> parse_range_step(part)
      part =~ ~r/^\d+\-\d+$/ -> parse_range(part)
      true -> raise ArgumentError, "unrecognized cron expression: #{part}"
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

    Enum.filter(range, &(rem(&1, step) == 0))
  end

  defp parse_range(part) do
    [rmin, rmax] = String.split(part, "-", parts: 2)

    String.to_integer(rmin)..String.to_integer(rmax)
  end

  defp parse_range_step(part) do
    [range, step] = String.split(part, "/")

    parse_step(step, parse_range(range))
  end
end
