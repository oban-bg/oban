defmodule Oban.Integration.CrontabTest do
  use Oban.Case

  @moduletag :integration

  @oban_opts repo: Repo, queues: [default: 5]

  test "cron jobs are enqueued on startup" do
    oban_opts =
      Keyword.put(@oban_opts, :crontab, [
        {"* * * * *", Worker, args: worker_args(1)},
        {"59 23 31 12 0", Worker, args: worker_args(2)},
        {"* * * * *", Worker, args: worker_args(3)},
        {"* * * * *", Worker, args: worker_args(4), queue: "alpha"}
      ])

    start_supervised!({Oban, oban_opts})

    assert_receive {:ok, 1}
    refute_receive {:ok, 2}
    assert_receive {:ok, 3}
    refute_receive {:ok, 4}

    :ok = stop_supervised(Oban)
  end

  test "cron jobs are not enqueued twice within the same minute" do
    oban_opts = Keyword.put(@oban_opts, :crontab, [{"* * * * *", Worker, args: worker_args(1)}])

    start_supervised!({Oban, oban_opts})

    assert_receive {:ok, 1}

    :ok = stop_supervised(Oban)

    start_supervised!({Oban, oban_opts})

    refute_receive {:ok, 1}

    :ok = stop_supervised(Oban)
  end

  defp worker_args(ref) do
    %{ref: ref, action: "OK", bin_pid: Worker.pid_to_bin()}
  end
end
