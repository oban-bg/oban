defmodule Oban.Integration.CrontabTest do
  use Oban.Case

  import Ecto.Query, only: [select: 2]

  @moduletag :integration

  test "cron jobs are enqueued on startup" do
    start_supervised_oban!(
      queues: [alpha: 5],
      crontab: [
        {"* * * * *", Worker, args: worker_args(1)},
        {"59 23 31 12 0", Worker, args: worker_args(2)},
        {"* * * * *", Worker, args: worker_args(3)},
        {"* * * * *", Worker, args: worker_args(4), queue: "gamma"}
      ]
    )

    assert_receive {:ok, 1}
    refute_receive {:ok, 2}
    assert_receive {:ok, 3}
    refute_receive {:ok, 4}
  end

  test "cron jobs are not enqueued twice within the same minute" do
    oban_opts = [
      queues: [alpha: 5],
      crontab: [{"* * * * *", Worker, args: worker_args(1)}]
    ]

    name = start_supervised_oban!(oban_opts)

    assert_receive {:ok, 1}

    :ok = stop_supervised(name)

    start_supervised_oban!(oban_opts)

    refute_receive {:ok, 1}
  end

  test "cron jobs are only enqueued once between nodes" do
    base_opts = [
      queues: [alpha: 5],
      crontab: [{"* * * * *", Worker, args: worker_args(1)}]
    ]

    name1 = start_supervised_oban!(base_opts)
    name2 = start_supervised_oban!(base_opts)

    assert_receive {:ok, 1}

    :ok = stop_supervised(name1)
    :ok = stop_supervised(name2)

    assert 1 == Job |> select(count()) |> Repo.one()
  end

  test "cron jobs are scheduled within a prefix" do
    base_opts = [
      queues: [alpha: 5],
      crontab: [{"* * * * *", Worker, args: worker_args(1)}]
    ]

    name1 = start_supervised_oban!(base_opts ++ [prefix: "public"])
    name2 = start_supervised_oban!(base_opts ++ [prefix: "private"])

    assert_receive {:ok, 1}
    assert_receive {:ok, 1}

    :ok = stop_supervised(name1)
    :ok = stop_supervised(name2)

    assert 1 == Job |> select(count()) |> Repo.one(prefix: "public")
    assert 1 == Job |> select(count()) |> Repo.one(prefix: "private")
  end

  test "cron jobs are scheduled using the configured timezone" do
    {:ok, %DateTime{hour: chi_hour}} = DateTime.now("America/Chicago")
    {:ok, %DateTime{hour: utc_hour}} = DateTime.now("Etc/UTC")

    start_supervised_oban!(
      queues: [alpha: 5],
      timezone: "America/Chicago",
      crontab: [
        {"* #{chi_hour} * * *", Worker, args: worker_args(1)},
        {"* #{utc_hour} * * *", Worker, args: worker_args(2)}
      ]
    )

    assert_receive {:ok, 1}
    refute_receive {:ok, 2}
  end

  test "reboot jobs are enqueued on startup" do
    name =
      start_supervised_oban!(
        queues: false,
        crontab: [{"@reboot", Worker, args: worker_args(1)}]
      )

    :ok = stop_supervised(name)

    assert 1 == Job |> select(count()) |> Repo.one()
  end

  test "reboot jobs are only enqueued once between nodes" do
    base_opts = [
      queues: false,
      crontab: [{"@reboot", Worker, args: worker_args(1)}]
    ]

    name1 = start_supervised_oban!(base_opts)
    name2 = start_supervised_oban!(base_opts)

    :ok = stop_supervised(name1)
    :ok = stop_supervised(name2)

    assert 1 == Job |> select(count()) |> Repo.one()
  end

  defp worker_args(ref) do
    %{ref: ref, action: "OK", bin_pid: Worker.pid_to_bin()}
  end
end
