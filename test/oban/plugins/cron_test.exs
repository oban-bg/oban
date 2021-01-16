defmodule Oban.Plugins.CronTest do
  use Oban.Case

  alias Oban.Plugins.Cron
  alias Oban.Registry

  @moduletag :integration

  describe "validate/1" do
    test ":crontab is validated as a list of cron job expressions" do
      refute_valid(crontab: ["* * * * *"])
      refute_valid(crontab: [["* * * * *", Fake]])
      refute_valid(crontab: [Worker])

      assert_valid(crontab: [{"* * * * *", Worker}])
      assert_valid(crontab: [{"* * * * *", Worker, queue: "special"}])
    end

    test ":timezone is validated as a known timezone" do
      refute_valid(timezone: "")
      refute_valid(timezone: nil)
      refute_valid(timezone: "america")
      refute_valid(timezone: "america/chicago")

      assert_valid(timezone: "Etc/UTC")
      assert_valid(timezone: "Europe/Copenhagen")
      assert_valid(timezone: "America/Chicago")
    end
  end

  test "cron jobs are enqueued on startup" do
    run_with_opts(
      crontab: [
        {"* * * * *", Worker, args: worker_args(1)},
        {"59 23 31 12 0", Worker, args: worker_args(2)},
        {"* * * * *", Worker, args: worker_args(3)}
      ]
    )

    assert inserted_refs() == [1, 3]
  end

  test "cron jobs are not enqueued twice within the same minute" do
    run_with_opts(crontab: [{"* * * * *", Worker, args: worker_args(1)}])

    assert inserted_refs() == [1]

    run_with_opts(crontab: [{"* * * * *", Worker, args: worker_args(1)}])

    assert inserted_refs() == [1]
  end

  test "cron jobs are only enqueued once between nodes" do
    opts = [crontab: [{"* * * * *", Worker, args: worker_args(1)}]]

    name1 = start_supervised_oban!(plugins: [{Cron, opts}])
    name2 = start_supervised_oban!(plugins: [{Cron, opts}])
    name3 = start_supervised_oban!(plugins: [{Cron, opts}])

    for name <- [name1, name2, name3], do: stop_supervised(name)

    assert inserted_refs() == [1]
  end

  test "cron jobs are scheduled using the configured timezone" do
    {:ok, %DateTime{hour: chi_hour}} = DateTime.now("America/Chicago")
    {:ok, %DateTime{hour: utc_hour}} = DateTime.now("Etc/UTC")

    run_with_opts(
      timezone: "America/Chicago",
      crontab: [
        {"* #{chi_hour} * * *", Worker, args: worker_args(1)},
        {"* #{utc_hour} * * *", Worker, args: worker_args(2)}
      ]
    )

    assert inserted_refs() == [1]
  end

  test "reboot jobs are enqueued on startup" do
    run_with_opts(crontab: [{"@reboot", Worker, args: worker_args(1)}])

    assert inserted_refs() == [1]
  end

  test "translating deprecated crontab/timezone config into plugin usage" do
    assert [timezone: "America/Chicago", crontab: [{"* * * * *", Worker}]]
           |> start_supervised_oban!()
           |> Registry.whereis({:plugin, Cron})

    assert [crontab: [{"* * * * *", Worker}]]
           |> start_supervised_oban!()
           |> Registry.whereis({:plugin, Cron})

    assert [plugins: [Oban.Plugins.Pruner], crontab: [{"* * * * *", Worker}]]
           |> start_supervised_oban!()
           |> Registry.whereis({:plugin, Cron})

    refute [plugins: false, crontab: [{"* * * * *", Worker}]]
           |> start_supervised_oban!()
           |> Registry.whereis({:plugin, Cron})

    refute [timezone: "America/Chicago"]
           |> start_supervised_oban!()
           |> Registry.whereis({:plugin, Cron})
  end

  defp assert_valid(opts) do
    assert :ok = Cron.validate!(opts)
  end

  defp refute_valid(opts) do
    assert_raise ArgumentError, fn -> Cron.validate!(opts) end
  end

  defp worker_args(ref) do
    %{ref: ref, action: "OK", bin_pid: Worker.pid_to_bin()}
  end

  defp run_with_opts(opts) do
    [plugins: [{Cron, opts}]]
    |> start_supervised_oban!()
    |> stop_supervised()
  end

  defp inserted_refs do
    Job
    |> Repo.all()
    |> Enum.map(fn job -> job.args["ref"] end)
    |> Enum.sort()
  end
end
