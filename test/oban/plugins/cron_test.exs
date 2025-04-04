defmodule Oban.Plugins.CronTest do
  use Oban.Case, async: true

  import Ecto.Query, only: [where: 2]

  alias Oban.Cron.Expression
  alias Oban.Plugins.Cron
  alias Oban.{Job, Registry, TelemetryHandler}

  defmodule CronWork do
    use Oban.Worker, queue: :cron

    @impl Oban.Worker
    def perform(_job), do: :ok
  end

  defmodule WorkerWithoutPerform do
  end

  describe "validate/1" do
    test ":crontab job format is validated" do
      refute_valid("expected crontab entry to be", crontab: ["* * * *"])
      refute_valid("expected crontab entry to be", crontab: ["* * * * *"])

      assert_valid(crontab: [{"* * * * *", CronWork}])
      assert_valid(crontab: [{"* * * * *", CronWork, queue: "special"}])
    end

    test ":crontab worker existence is validated" do
      refute_valid("Fake not found", crontab: [{"* * * * *", CronWork}, {"* * * * *", Fake}])
    end

    test ":crontab worker perform/1 callback is validated" do
      refute_valid("WorkerWithoutPerform does not implement `perform/1`",
        crontab: [{"* * * * *", WorkerWithoutPerform}]
      )
    end

    test ":crontab worker options format is validated" do
      refute_valid("options must be a keyword list",
        crontab: [{"* * * * *", CronWork, %{foo: "bar"}}]
      )
    end

    test ":crontab worker range expression is validated" do
      refute_valid(crontab: [{"* * * * SAT-SUN", CronWork}])
    end

    test ":crontab worker options are validated" do
      refute_valid("expected valid job options", crontab: [{"* * * * *", CronWork, priority: -1}])
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

    test "providing suggestions for unknown options" do
      assert {:error, "unknown option :cronta, did you mean :crontab?"} =
               Cron.validate(cronta: [])
    end
  end

  describe "parse/1" do
    test "returning valid expressions in a success tuple" do
      assert {:ok, %Expression{}} = Cron.parse("0 0 1 * *")
    end

    test "wrapping invalid expressions in an error tuple" do
      assert {:error, %ArgumentError{}} = Cron.parse("60 24 13 * *")
    end
  end

  test "cron jobs are enqueued on startup and telemetry events are emitted" do
    TelemetryHandler.attach_events()

    run_with_opts(
      crontab: [
        {"* * * * *", CronWork, args: worker_args(1)},
        {"59 23 31 12 0", CronWork, args: worker_args(2)},
        {"* * * * *", CronWork, args: worker_args(3)}
      ]
    )

    assert_receive {:event, :start, %{system_time: _}, %{conf: _, plugin: Cron}}

    assert_receive {:event, :stop, %{duration: _},
                    %{conf: _, jobs: [%Job{}, %Job{}], plugin: Cron}}

    assert [1, 3] == inserted_refs()
  end

  test "cron jobs are scheduled using the configured timezone" do
    {:ok, %DateTime{hour: chi_hour}} = DateTime.now("America/Chicago")
    {:ok, %DateTime{hour: utc_hour}} = DateTime.now("Etc/UTC")

    run_with_opts(
      timezone: "America/Chicago",
      crontab: [
        {"* #{chi_hour} * * *", CronWork, args: worker_args(1)},
        {"* #{utc_hour} * * *", CronWork, args: worker_args(2)}
      ]
    )

    assert [1] == inserted_refs()
  end

  test "cron schedules are injected into the enqueued job's meta" do
    run_with_opts(
      timezone: "America/Chicago",
      crontab: [
        {"@reboot", CronWork, args: worker_args(1)},
        {"* * * * *", CronWork, args: worker_args(2)}
      ]
    )

    assert [{true, "* * * * *", "America/Chicago"}, {true, "@reboot", "America/Chicago"}] ==
             Job
             |> Repo.all()
             |> Enum.map(&{&1.meta["cron"], &1.meta["cron_expr"], &1.meta["cron_tz"]})
             |> Enum.sort()
  end

  test "reboot jobs are enqueued on startup" do
    run_with_opts(crontab: [{"@reboot", CronWork, args: worker_args(1)}])

    assert [1] == inserted_refs()
  end

  test "evaluating reboot after acquiring leadership" do
    name =
      start_supervised_oban!(
        peer: {Oban.Peers.Isolated, leader?: false},
        plugins: [{Cron, crontab: [{"@reboot", CronWork, args: worker_args(1)}]}]
      )

    send_evaluate(name)

    assert [] == inserted_refs()

    name
    |> Registry.whereis(Oban.Peer)
    |> Agent.update(&%{&1 | leader?: true})

    send_evaluate(name)

    assert [1] == inserted_refs()

    stop_supervised!(name)
  end

  defp assert_valid(opts) do
    assert :ok = Cron.validate(opts)
  end

  defp refute_valid(opts) do
    assert {:error, _} = Cron.validate(opts)
  end

  defp refute_valid(message, opts) do
    assert {:error, error} = Cron.validate(opts)
    assert error =~ message
  end

  defp worker_args(ref) do
    %{ref: ref, action: "OK"}
  end

  defp run_with_opts(opts) do
    [plugins: [{Cron, opts}]]
    |> start_supervised_oban!()
    |> send_evaluate()
    |> stop_supervised()
  end

  defp send_evaluate(name) do
    name
    |> Registry.whereis({:plugin, Cron})
    |> tap(&send(&1, :evaluate))
    |> :sys.log(true)

    name
  end

  defp inserted_refs do
    Job
    |> where(queue: "cron")
    |> Repo.all()
    |> Enum.map(fn job -> job.args["ref"] end)
    |> Enum.sort()
  end
end
