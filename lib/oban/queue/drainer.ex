defmodule Oban.Queue.Drainer do
  @moduledoc false

  alias Oban.{Config, Query}
  alias Oban.Queue.Executor

  @unlimited 100_000_000
  @far_future DateTime.from_unix!(9_999_999_999)

  @type drain_option :: {:with_scheduled, boolean()} | {:with_safety, boolean()}
  @type drain_result :: %{success: non_neg_integer(), failure: non_neg_integer()}

  @spec drain(Config.t(), binary(), [drain_option()]) :: drain_result()
  def drain(%Config{} = conf, queue, opts \\ []) when is_binary(queue) and is_list(opts) do
    if Keyword.get(opts, :with_scheduled, false), do: schedule_jobs(conf, queue)

    conf
    |> fetch_jobs(queue)
    |> Enum.reduce(%{failure: 0, success: 0}, fn job, acc ->
      result =
        conf
        |> Executor.new(job)
        |> Executor.put(:safe, Keyword.get(opts, :with_safety, true))
        |> Executor.call()

      Map.update(acc, result, 1, &(&1 + 1))
    end)
  end

  defp schedule_jobs(conf, queue) do
    Query.stage_scheduled_jobs(conf, queue, max_scheduled_at: @far_future)
  end

  defp fetch_jobs(conf, queue) do
    {:ok, jobs} = Query.fetch_available_jobs(conf, queue, "draining", @unlimited)

    jobs
  end
end
