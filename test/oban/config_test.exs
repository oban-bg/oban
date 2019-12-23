defmodule Oban.ConfigTest do
  use Oban.Case, async: true

  alias Oban.Config

  describe "start_link/1" do
    test "a config struct is stored for retreival" do
      conf = Config.new(repo: Repo)

      {:ok, pid} = Config.start_link(conf: conf)

      assert %Config{} = Config.get(pid)
    end
  end

  describe "new/1" do
    test ":circuit_backoff is validated as an integer" do
      assert_invalid(circuit_backoff: -1)
      assert_invalid(circuit_backoff: 0)
      assert_invalid(circuit_backoff: "5")
      assert_invalid(circuit_backoff: 1.0)

      assert_valid(circuit_backoff: 10)
    end

    test ":dispatch_cooldown is validated as a positive integer" do
      assert_invalid(dispatch_cooldown: -1)
      assert_invalid(dispatch_cooldown: 0)
      assert_invalid(dispatch_cooldown: "5")
      assert_invalid(dispatch_cooldown: 1.0)

      assert_valid(dispatch_cooldown: 500)
    end

    test ":crontab is validated as a list of cron job expressions" do
      assert_invalid(crontab: ["* * * * *"])
      assert_invalid(crontab: [["* * * * *", Fake]])
      assert_invalid(crontab: [Worker])

      config = assert_valid(crontab: [{"* * * * *", Worker}])
      assert [{%_{minutes: _}, Worker, []}] = config.crontab

      config = assert_valid(crontab: [{"* * * * *", Worker, queue: "special"}])
      assert [{%_{minutes: _}, Worker, [queue: "special"]}] = config.crontab

      assert %Config{crontab: []} = conf(crontab: false)
    end

    test ":name is validated as a module" do
      assert_invalid(name: "Oban")
      assert_invalid(name: {:via, :whatever})

      assert_valid(name: MyOban)
    end

    test ":node is validated as a binary" do
      assert_invalid(node: nil)
      assert_invalid(node: '')
      assert_invalid(node: "")
      assert_invalid(node: MyNode)

      assert_valid(node: "MyNode")
    end

    test ":poll_interval is validated as an integer" do
      assert_invalid(poll_interval: -1)
      assert_invalid(poll_interval: 0)
      assert_invalid(poll_interval: "5")
      assert_invalid(poll_interval: 1.0)

      assert_valid(poll_interval: 10)
    end

    test ":prefix is validated as a binary" do
      assert_invalid(prefix: :private)
      assert_invalid(prefix: " private schema ")
      assert_invalid(prefix: "")

      assert_valid(prefix: "private")
    end

    test ":prune is validated as disabled or a max* option" do
      assert_invalid(prune: :unknown)
      assert_invalid(prune: 5)
      assert_invalid(prune: "disabled")
      assert_invalid(prune: {:maxlen, "1"})
      assert_invalid(prune: {:maxlen, -5})
      assert_invalid(prune: {:maxage, "1"})
      assert_invalid(prune: {:maxage, -5})

      assert_valid(prune: :disabled)
      assert_valid(prune: {:maxlen, 10})
      assert_valid(prune: {:maxage, 10})
    end

    test ":prune_interval is validated as a positive integer" do
      assert_invalid(prune_interval: -1)
      assert_invalid(prune_interval: 0)
      assert_invalid(prune_interval: "5")
      assert_invalid(prune_interval: 1.0)

      assert_valid(prune_interval: 500)
    end

    test ":prune_limit is validated as a positive integer" do
      assert_invalid(prune_limit: -1)
      assert_invalid(prune_limit: 0)
      assert_invalid(prune_limit: "5")
      assert_invalid(prune_limit: 1.0)

      assert_valid(prune_limit: 5_000)
    end

    test ":queues are validated as atom, integer pairs" do
      assert_invalid(queues: %{default: 25})
      assert_invalid(queues: [{"default", 25}])
      assert_invalid(queues: [default: 0])
      assert_invalid(queues: [default: 3.5])

      assert_valid(queues: [default: 1])

      assert %Config{queues: []} = conf(queues: false)
    end

    test ":rescue_after is validated as an integer" do
      assert_invalid(rescue_after: -1)
      assert_invalid(rescue_after: 0)
      assert_invalid(rescue_after: "5")
      assert_invalid(rescue_after: 1.0)

      assert_valid(rescue_after: 30)
    end

    test ":rescue_interval is validated as an integer" do
      assert_invalid(rescue_interval: -1)
      assert_invalid(rescue_interval: 0)
      assert_invalid(rescue_interval: "5")
      assert_invalid(rescue_interval: 1.0)

      assert_valid(rescue_interval: 10)
    end

    test ":shutdown_grace_period is validated as an integer" do
      assert_invalid(shutdown_grace_period: -1)
      assert_invalid(shutdown_grace_period: 0)
      assert_invalid(shutdown_grace_period: "5")
      assert_invalid(shutdown_grace_period: 1.0)

      assert_valid(shutdown_grace_period: 10)
    end

    test ":timezone is validated as a known timezone" do
      assert_invalid(timezone: "")
      assert_invalid(timezone: nil)
      assert_invalid(timezone: "america")
      assert_invalid(timezone: "america/chicago")

      assert_valid(timezone: "Etc/UTC")
      assert_valid(timezone: "Europe/Copenhagen")
      assert_valid(timezone: "America/Chicago")
    end

    test ":verbose is validated as `false` or a valid log level" do
      assert_invalid(verbose: 1)
      assert_invalid(verbose: "false")
      assert_invalid(verbose: nil)
      assert_invalid(verbose: :warning)
      assert_invalid(verbose: true)

      assert_valid(verbose: false)
      assert_valid(verbose: :warn)
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

  defp assert_invalid(opts) do
    assert_raise ArgumentError, fn -> conf(opts) end
  end

  defp assert_valid(opts) do
    assert %Config{} = conf(opts)
  end

  defp conf(opts) do
    opts
    |> Keyword.put(:repo, Repo)
    |> Config.new()
  end
end
