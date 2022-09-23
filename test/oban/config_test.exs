defmodule Oban.ConfigTest do
  use Oban.Case, async: true

  alias Oban.Config
  alias Oban.Plugins.{Cron, Pruner, Stager}

  doctest Config

  describe "validate/1" do
    test "legacy :circuit_backoff option is ignored" do
      assert_valid(circuit_backoff: 10)
    end

    test ":engine is validated as an engine module" do
      refute_valid(engine: nil)
      refute_valid(engine: Repo)

      assert_valid(engine: Oban.Engines.Basic)
      assert_valid(engine: Oban.Engines.Inline)
    end

    test ":log is validated as `false` or a valid log level" do
      refute_valid(log: 1)
      refute_valid(log: "false")
      refute_valid(log: nil)
      refute_valid(log: :nothing)
      refute_valid(log: true)

      assert_valid(log: false)
      assert_valid(log: :warn)
      assert_valid(log: :warning)
      assert_valid(log: :alert)
      assert_valid(log: :debug)
    end

    test ":notifier is validated as a notifier module" do
      refute_valid(notifier: nil)
      refute_valid(notifier: Repo)

      assert_valid(notifier: Oban.Notifiers.Postgres)
    end

    test ":node is validated as a binary" do
      refute_valid(node: nil)
      refute_valid(node: '')
      refute_valid(node: "")
      refute_valid(node: "  ")
      refute_valid(node: MyNode)

      assert_valid(node: "MyNode")
    end

    test ":peer is validated as false or a peer module" do
      refute_valid(peer: nil)
      refute_valid(peer: Fake)

      assert_valid(peer: false)
      assert_valid(peer: Oban.Peers.Global)
      assert_valid(peer: Oban.Peers.Postgres)
    end

    test ":plugins are validated as complete plugins with possible options" do
      refute_valid(plugins: ["Module"])
      refute_valid(plugins: [FakeModule])
      refute_valid(plugins: [Pruner, FakeModule])
      refute_valid(plugins: [{Worker, nil}])
      refute_valid(plugins: [{Worker, %{}}])
      refute_valid(plugins: [{Pruner, interval: -1}])

      assert_valid(plugins: false)
      assert_valid(plugins: [])
      assert_valid(plugins: [Pruner])
      assert_valid(plugins: [{Pruner, []}])
      assert_valid(plugins: [{Pruner, [name: "Something"]}])
    end

    test ":prefix is validated as a binary" do
      refute_valid(prefix: :private)
      refute_valid(prefix: " private schema ")
      refute_valid(prefix: "")

      assert_valid(prefix: "private")
    end

    test ":queues are validated as an initializable keyword list" do
      refute_valid(queues: %{default: 25})
      refute_valid(queues: [{"default", 25}])
      refute_valid(queues: [default: 0])
      refute_valid(queues: [default: 3.5])
      refute_valid(queues: [default: [lim: 1]])
      refute_valid(queues: [default: [limit: 1, paused: :yes]])

      assert_valid(queues: [default: 1])
      assert_valid(queues: [default: [limit: 1]])
      assert_valid(queues: [default: [limit: 1, paused: true]])
      assert_valid(queues: [default: [limit: 1, dispatch_cooldown: 10]])
    end

    test ":shutdown_grace_period is validated as an integer" do
      refute_valid(shutdown_grace_period: -1)
      refute_valid(shutdown_grace_period: "5")
      refute_valid(shutdown_grace_period: 1.0)

      assert_valid(shutdown_grace_period: 0)
      assert_valid(shutdown_grace_period: 10)
    end

    test ":testing is validated as a boolean" do
      refute_valid(testing: :ok)
      refute_valid(testing: true)

      assert_valid(testing: :inline)
      assert_valid(testing: :manual)
      assert_valid(testing: :disabled)
    end
  end

  describe "new/1" do
    test ":notifier translates to the correct postgres module" do
      assert %Config{notifier: Oban.Notifiers.Postgres} = conf(notifier: Oban.PostgresNotifier)
    end

    test ":engine translates to the correct basic module" do
      assert %Config{engine: Oban.Engines.Basic} = conf(engine: Oban.Queue.BasicEngine)
    end

    test ":queues convert to an empty list when set to false" do
      assert %Config{queues: []} = conf(queues: false)
    end

    test ":testing in :manual mode disables queues, peer, and plugins" do
      assert %Config{queues: [], plugins: [], peer: Oban.Peers.Disabled} =
               conf(queues: [alpha: 1], plugins: [Pruner], testing: :manual)
    end

    test "translating deprecated crontab/timezone config into plugin usage" do
      assert has_plugin?(Cron, timezone: "America/Chicago", crontab: [{"* * * * *", Worker}])
      assert has_plugin?(Cron, crontab: [{"* * * * *", Worker}])
      assert has_plugin?(Cron, plugins: [Pruner], crontab: [{"* * * * *", Worker}])

      refute has_plugin?(Cron, timezone: "America/Chicago")
      refute has_plugin?(Cron, plugins: false, crontab: [{"* * * * *", Worker}])
    end

    test "translating poll_interval config into plugin usage" do
      assert has_plugin?(Stager, [])
      assert has_plugin?(Stager, poll_interval: 2000)

      refute has_plugin?(Stager, plugins: false, poll_interval: 2000)
    end

    test "translating peer false to the disabled module" do
      assert %Config{peer: Oban.Peers.Disabled} = conf(peer: false)
      assert %Config{peer: Oban.Peers.Disabled} = conf(plugins: false)
    end
  end

  describe "node_name/1" do
    test "the system's DYNO value is favored when available" do
      assert Config.node_name(%{"DYNO" => "worker.1"}) == "worker.1"
    end

    test "the local hostname is used without a DYNO variable" do
      hostname = Config.node_name()

      assert is_binary(hostname)
      assert String.length(hostname) > 1
    end
  end

  defp refute_valid(opts) do
    assert {:error, _reason} = Config.validate(opts)
  end

  defp assert_valid(opts) do
    assert :ok = Config.validate(opts)
  end

  defp conf(opts) do
    opts
    |> Keyword.put(:repo, Repo)
    |> Config.new()
  end

  def has_plugin?(plugin, opts) do
    plugins =
      opts
      |> conf()
      |> Map.fetch!(:plugins)
      |> Enum.map(fn
        {module, _opts} -> module
        module -> module
      end)

    plugin in plugins
  end
end
