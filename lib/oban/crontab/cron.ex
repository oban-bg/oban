defmodule Oban.Crontab.Cron do
  @moduledoc false

  alias Oban.Crontab.Parser

  @type expression :: [:*] | list(non_neg_integer())

  @type t :: %__MODULE__{
          minutes: expression(),
          hours: expression(),
          days: expression(),
          months: expression(),
          weekdays: expression(),
          reboot: boolean()
        }

  @part_ranges %{
    minutes: {0, 59},
    hours: {0, 23},
    days: {1, 31},
    months: {1, 12},
    weekdays: {0, 6}
  }

  defstruct minutes: [:*], hours: [:*], days: [:*], months: [:*], weekdays: [:*], reboot: false

  @spec now?(cron :: t(), datetime :: DateTime.t()) :: boolean()
  def now?(cron, datetime \\ DateTime.utc_now())

  def now?(%__MODULE__{reboot: true}, _datetime), do: false

  def now?(%__MODULE__{} = cron, datetime) do
    cron
    |> Map.from_struct()
    |> Map.drop([:reboot])
    |> Enum.all?(fn {part, values} ->
      Enum.any?(values, &matches_rule?(part, &1, datetime))
    end)
  end

  defp matches_rule?(_part, :*, _date_time), do: true
  defp matches_rule?(:minutes, minute, datetime), do: minute == datetime.minute
  defp matches_rule?(:hours, hour, datetime), do: hour == datetime.hour
  defp matches_rule?(:days, day, datetime), do: day == datetime.day
  defp matches_rule?(:months, month, datetime), do: month == datetime.month
  defp matches_rule?(:weekdays, weekday, datetime), do: weekday == day_of_week(datetime)

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
  def parse!("@annually"), do: parse!("@yearly")
  def parse!("@yearly"), do: parse!("0 0 1 1 *")
  def parse!("@monthly"), do: parse!("0 0 1 * *")
  def parse!("@weekly"), do: parse!("0 0 * * 0")
  def parse!("@midnight"), do: parse!("@daily")
  def parse!("@daily"), do: parse!("0 0 * * *")
  def parse!("@hourly"), do: parse!("0 * * * *")
  def parse!("@reboot"), do: struct!(__MODULE__, reboot: true)

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

  defp expand({:step, [{:wild, _}, value]}, min, max) when value > 0 and value in min..max do
    for step <- min..max, rem(step, value) == 0, do: step
  end

  defp expand({:step, [{:range, [first, last]}, value]}, min, max)
       when first >= min and last <= max and last > first and value <= last - first do
    for step <- first..last, rem(step, value) == 0, do: step
  end

  defp expand({:range, [first, last]}, min, max) when first >= min and last <= max do
    for step <- first..last, do: step
  end

  defp expand({_type, value}, min, max) do
    raise ArgumentError, "Unexpected value #{inspect(value)} outside of range #{min}..#{max}"
  end

  @spec reboot?(cron :: t()) :: boolean()
  def reboot?(%__MODULE__{reboot: reboot}), do: reboot
end
