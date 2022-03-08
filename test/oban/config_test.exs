defmodule Oban.ConfigTest do
  use Oban.Case, async: true

  alias Oban.Config
  alias Oban.Plugins.Pruner

  doctest Config

  describe "new/1" do
    test "legacy :circuit_backoff option is ignored" do
      assert_valid(circuit_backoff: 10)
    end

    test ":engine is validated as an engine module" do
      refute_valid(engine: nil)
      refute_valid(engine: Repo)

      assert_valid(engine: Oban.Queue.BasicEngine)
    end

    test ":notifier is validated as a notifier module" do
      refute_valid(notifier: nil)
      refute_valid(notifier: Repo)

      assert_valid(notifier: Oban.Notifiers.Postgres)

      assert %Config{notifier: Oban.Notifiers.Postgres} = conf(notifier: Oban.PostgresNotifier)
    end

    test ":peer is validated as false or a peer module" do
      refute_valid(peer: nil)
      refute_valid(peer: Fake)

      assert_valid(peer: false)
      assert_valid(peer: Oban.Peer)
    end

    test ":node is validated as a binary" do
      refute_valid(node: nil)
      refute_valid(node: '')
      refute_valid(node: "")
      refute_valid(node: "  ")
      refute_valid(node: MyNode)

      assert_valid(node: "MyNode")
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

    test ":queues are validated as atom, integer pairs or atom, keyword pairs" do
      refute_valid(queues: %{default: 25})
      refute_valid(queues: [{"default", 25}])
      refute_valid(queues: [default: 0])
      refute_valid(queues: [default: 3.5])

      assert_valid(queues: [default: 1])
      assert_valid(queues: [default: [limit: 1]])

      assert %Config{queues: []} = conf(queues: false)
    end

    test ":shutdown_grace_period is validated as an integer" do
      refute_valid(shutdown_grace_period: -1)
      refute_valid(shutdown_grace_period: 0)
      refute_valid(shutdown_grace_period: "5")
      refute_valid(shutdown_grace_period: 1.0)

      assert_valid(shutdown_grace_period: 10)
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
end
