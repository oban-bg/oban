defmodule Oban.Plugins.CronTest do
  use Oban.Case

  alias Oban.Plugins.Cron
  alias Oban.{Job, PluginTelemetryHandler, Registry}

  @moduletag :integration

  defmodule WorkerWithoutPerform do
  end

  describe "validate/1" do
    test ":crontab is validated as a list of cron job expressions" do
      assert_raise ArgumentError, ~r/expected :crontab to be a list/, fn ->
        Cron.validate!(crontab: %{worker1: "foo"})
      end
    end

    test "job format is validated" do
      assert_raise ArgumentError, ~r/expected crontab entry to be an {expression, worker}/, fn ->
        Cron.validate!(crontab: ["* * * * *"])
      end

      assert_valid(crontab: [{"* * * * *", Worker}])
      assert_valid(crontab: [{"* * * * *", Worker, queue: "special"}])
    end

    test "worker existence is validated" do
      assert_raise ArgumentError, "Fake not found or can't be loaded", fn ->
        Cron.validate!(crontab: [{"* * * * *", Worker}, {"* * * * *", Fake}])
      end
    end

    test "worker perform/1 callback is validated" do
      assert_raise ArgumentError, ~r|WorkerWithoutPerform does not implement `perform/1`|, fn ->
        Cron.validate!(crontab: [{"* * * * *", WorkerWithoutPerform}])
      end
    end

    test "worker options format is validated" do
      assert_raise ArgumentError, ~r/options must be a keyword list/, fn ->
        Cron.validate!(crontab: [{"* * * * *", Worker, %{foo: "bar"}}])
      end
    end

    test "worker options are validated" do
      assert_raise ArgumentError, ~r/expected valid job options/, fn ->
        Cron.validate!(crontab: [{"* * * * *", Worker, priority: -1}])
      end

      assert_raise ArgumentError, ~r/expected valid job options/, fn ->
        Cron.validate!(crontab: [{"* * * * *", Worker, unique: []}])
      end
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

  describe "interval_to_next_minute/1" do
    property "calculated time is always within a short future range" do
      check all hour <- integer(0..23),
                minute <- integer(0..59),
                second <- integer(0..59),
                max_runs: 1_000 do
        {:ok, time} = Time.new(hour, minute, second)

        assert Cron.interval_to_next_minute(time) in 1_000..60_000
      end
    end
  end

  test "cron jobs are enqueued on startup and telemetry events are emitted" do
    PluginTelemetryHandler.attach_plugin_events("plugin-cron-handler")

    run_with_opts(
      crontab: [
        {"* * * * *", Worker, args: worker_args(1)},
        {"59 23 31 12 0", Worker, args: worker_args(2)},
        {"* * * * *", Worker, args: worker_args(3)}
      ]
    )

    assert_receive {:event, :start, %{system_time: _}, %{conf: _, plugin: Cron}}

    assert_receive {:event, :stop, %{duration: _},
                    %{conf: _, jobs: [%Job{}, %Job{}], plugin: Cron}}

    assert inserted_refs() == [1, 3]
  after
    :telemetry.detach("plugin-cron-handler")
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

  test "reboot jobs with specified timezone are also enqueued on startup" do
    run_with_opts(
      crontab: [{"@reboot", Worker, args: worker_args(1)}],
      timezone: "America/Chicago"
    )

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
