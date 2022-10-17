defmodule Oban.Cron.Expression do
  @moduledoc false

  @type t :: %__MODULE__{
          minutes: MapSet.t(),
          hours: MapSet.t(),
          days: MapSet.t(),
          months: MapSet.t(),
          weekdays: MapSet.t(),
          reboot?: boolean()
        }

  defstruct [:minutes, :hours, :days, :months, :weekdays, reboot?: false]

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

  @spec now?(cron :: t(), datetime :: DateTime.t()) :: boolean()
  def now?(cron, datetime \\ DateTime.utc_now())

  def now?(%__MODULE__{reboot?: true}, _datetime), do: true

  def now?(%__MODULE__{} = cron, datetime) do
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
  defp included?({:reboot?, _}, _datetime), do: true

  defp day_of_week(datetime) do
    datetime
    |> Date.day_of_week()
    |> Integer.mod(7)
  end

  @spec parse!(input :: binary()) :: t()
  def parse!("@annually"), do: parse!("0 0 1 1 *")
  def parse!("@yearly"), do: parse!("0 0 1 1 *")
  def parse!("@monthly"), do: parse!("0 0 1 * *")
  def parse!("@weekly"), do: parse!("0 0 * * 0")
  def parse!("@midnight"), do: parse!("0 0 * * *")
  def parse!("@daily"), do: parse!("0 0 * * *")
  def parse!("@hourly"), do: parse!("0 * * * *")
  def parse!("@reboot"), do: %__MODULE__{reboot?: true}

  def parse!(input) when is_binary(input) do
    case String.split(input, ~r/\s+/, trim: true, parts: 5) do
      [mip, hrp, dap, mop, wdp] ->
        %__MODULE__{
          minutes: parse_field(mip, 0..59),
          hours: parse_field(hrp, 0..23),
          days: parse_field(dap, 1..31),
          months: mop |> trans_field(@mon_map) |> parse_field(1..12),
          weekdays: wdp |> trans_field(@dow_map) |> parse_field(0..6)
        }

      _parts ->
        raise ArgumentError, "incorrect number of fields in expression: #{input}"
    end
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
      part =~ ~r/^\d+(\-\d+)?\/[1-9]\d?$/ -> parse_range_step(part, range)
      part =~ ~r/^\d+\-\d+$/ -> parse_range(part, range)
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
        String.to_integer(rmin)..String.to_integer(rmax)
    end
  end
end
