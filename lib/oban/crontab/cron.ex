defmodule Oban.Crontab.Cron do
  @moduledoc false

  alias Oban.Crontab.Parser

  @type expression :: [:*] | list(non_neg_integer())

  @type t :: %__MODULE__{
          minutes: expression(),
          hours: expression(),
          days: expression(),
          months: expression(),
          weekdays: expression()
        }

  @part_ranges %{
    minutes: {0, 59},
    hours: {0, 23},
    days: {1, 31},
    months: {1, 12},
    weekdays: {0, 6}
  }

  defstruct minutes: [:*], hours: [:*], days: [:*], months: [:*], weekdays: [:*]

  @spec now?(cron :: t(), datetime :: DateTime.t()) :: boolean()
  def now?(%__MODULE__{} = cron, datetime \\ DateTime.utc_now()) do
    cron
    |> Map.from_struct()
    |> Enum.all?(fn {part, values} ->
      Enum.any?(values, &matches_rule?(part, &1, datetime))
    end)
  end

  defp matches_rule?(_part, :*, _date_time), do: true
  defp matches_rule?(:minutes, minute, datetime), do: minute == datetime.minute
  defp matches_rule?(:hours, hour, datetime), do: hour == datetime.hour
  defp matches_rule?(:days, day, datetime), do: day == datetime.day
  defp matches_rule?(:months, month, datetime), do: month == datetime.month
  defp matches_rule?(:weekdays, weekday, datetime), do: weekday == Date.day_of_week(datetime)

  @spec parse!(input :: binary()) :: t()
  def parse!(input) when is_binary(input) do
    input
    |> String.trim()
    |> Parser.cron()
    |> case do
      {:ok, parsed, _, _, _, _} ->
        struct!(__MODULE__, expand(parsed))

      {:error, message, _, _, _, _} ->
        raise ArgumentError, message
    end
  end

  defp expand(parsed) when is_list(parsed), do: Enum.map(parsed, &expand/1)

  defp expand({part, expressions}) do
    {min, max} = Map.get(@part_ranges, part)

    expanded =
      expressions
      |> Enum.flat_map(&expand(&1, min, max))
      |> :lists.usort()

    {part, expanded}
  end

  defp expand({:wild, _value}, _min, _max), do: [:*]

  defp expand({:literal, value}, min, max) when value in min..max, do: [value]

  defp expand({:step, value}, min, max) when value in (min + 1)..max do
    for step <- min..max, rem(step, value) == 0, do: step
  end

  defp expand({:range, [first, last]}, min, max) when first >= min and last <= max do
    for step <- first..last, do: step
  end

  defp expand({_type, value}, min, max) do
    raise ArgumentError, "Unexpected value #{inspect(value)} outside of range #{min}..#{max}"
  end
end
