defmodule Oban.Cron do
  @moduledoc false

  alias Oban.Cron.Expression

  @spec schedule_interval(pid(), term(), binary(), Calendar.time_zone()) :: :ok
  def schedule_interval(pid, message, schedule, timezone \\ "Etc/UTC") do
    :timer.apply_after(
      interval_to_next_minute(),
      __MODULE__,
      :__schedule_interval__,
      [pid, message, schedule, timezone]
    )

    :ok
  end

  @doc false
  def __schedule_interval__(pid, message, schedule, timezone) do
    exp = Expression.parse!(schedule)
    now = DateTime.now!(timezone)

    if Expression.now?(exp, now) do
      send(pid, message)
    end

    schedule_interval(pid, message, schedule, timezone)
  end

  @spec interval_to_next_minute(Time.t()) :: pos_integer()
  def interval_to_next_minute(time \\ Time.utc_now()) do
    time
    |> Time.add(60)
    |> Map.put(:second, 0)
    |> Time.diff(time)
    |> Integer.mod(86_400)
    |> :timer.seconds()
  end
end
