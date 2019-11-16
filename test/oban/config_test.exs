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
      assert_raise ArgumentError, fn -> Config.new(repo: Repo, circuit_backoff: -1) end
      assert_raise ArgumentError, fn -> Config.new(repo: Repo, circuit_backoff: 0) end
      assert_raise ArgumentError, fn -> Config.new(repo: Repo, circuit_backoff: "5") end
      assert_raise ArgumentError, fn -> Config.new(repo: Repo, circuit_backoff: 1.0) end

      assert %Config{} = Config.new(repo: Repo, circuit_backoff: 10)
    end

    test ":crontab is validated as a list of cron job expressions" do
      assert_raise ArgumentError, fn -> Config.new(repo: Repo, crontab: ["* * * * *"]) end
      assert_raise ArgumentError, fn -> Config.new(repo: Repo, crontab: [["* * * * *", Fake]]) end
      assert_raise ArgumentError, fn -> Config.new(repo: Repo, crontab: [Worker]) end

      assert %Config{crontab: crontab} = Config.new(repo: Repo, crontab: [{"* * * * *", Worker}])
      assert [{%_{minutes: _}, Worker, []}] = crontab

      assert %Config{crontab: crontab} =
               Config.new(
                 repo: Repo,
                 crontab: [{"* * * * *", Worker, queue: "special"}]
               )

      assert [{%_{minutes: _}, Worker, [queue: "special"]}] = crontab
    end

    test ":name is validated as a module" do
      assert_raise ArgumentError, fn -> Config.new(repo: Repo, name: "Oban") end
      assert_raise ArgumentError, fn -> Config.new(repo: Repo, name: {:via, :whatever}) end

      assert %Config{} = Config.new(repo: Repo, name: MyOban)
    end

    test ":node is validated as a binary" do
      assert_raise ArgumentError, fn -> Config.new(repo: Repo, node: nil) end
      assert_raise ArgumentError, fn -> Config.new(repo: Repo, node: '') end
      assert_raise ArgumentError, fn -> Config.new(repo: Repo, node: "") end
      assert_raise ArgumentError, fn -> Config.new(repo: Repo, node: MyNode) end

      assert %Config{} = Config.new(repo: Repo, node: "MyNode")
    end

    test ":poll_interval is validated as an integer" do
      assert_raise ArgumentError, fn -> Config.new(repo: Repo, poll_interval: -1) end
      assert_raise ArgumentError, fn -> Config.new(repo: Repo, poll_interval: 0) end
      assert_raise ArgumentError, fn -> Config.new(repo: Repo, poll_interval: "5") end
      assert_raise ArgumentError, fn -> Config.new(repo: Repo, poll_interval: 1.0) end

      assert %Config{} = Config.new(repo: Repo, poll_interval: 10)
    end

    test ":prefix is validated as a binary" do
      assert_raise ArgumentError, fn -> Config.new(repo: Repo, prefix: :private) end
      assert_raise ArgumentError, fn -> Config.new(repo: Repo, prefix: " private schema ") end
      assert_raise ArgumentError, fn -> Config.new(repo: Repo, prefix: "") end

      assert %Config{} = Config.new(repo: Repo, prefix: "private")
    end

    test ":prune is validated as disabled or a max* option" do
      assert_raise ArgumentError, fn -> Config.new(repo: Repo, prune: :unknown) end
      assert_raise ArgumentError, fn -> Config.new(repo: Repo, prune: 5) end
      assert_raise ArgumentError, fn -> Config.new(repo: Repo, prune: "disabled") end
      assert_raise ArgumentError, fn -> Config.new(repo: Repo, prune: {:maxlen, "1"}) end
      assert_raise ArgumentError, fn -> Config.new(repo: Repo, prune: {:maxlen, -5}) end
      assert_raise ArgumentError, fn -> Config.new(repo: Repo, prune: {:maxage, "1"}) end
      assert_raise ArgumentError, fn -> Config.new(repo: Repo, prune: {:maxage, -5}) end

      assert %Config{} = Config.new(repo: Repo, prune: :disabled)
      assert %Config{} = Config.new(repo: Repo, prune: {:maxlen, 10})
      assert %Config{} = Config.new(repo: Repo, prune: {:maxage, 10})
    end

    test ":prune_interval is validated as a positive integer" do
      assert_raise ArgumentError, fn -> Config.new(repo: Repo, prune_interval: -1) end
      assert_raise ArgumentError, fn -> Config.new(repo: Repo, prune_interval: 0) end
      assert_raise ArgumentError, fn -> Config.new(repo: Repo, prune_interval: "5") end
      assert_raise ArgumentError, fn -> Config.new(repo: Repo, prune_interval: 1.0) end

      assert %Config{} = Config.new(repo: Repo, prune_interval: 500)
    end

    test ":prune_limit is validated as a positive integer" do
      assert_raise ArgumentError, fn -> Config.new(repo: Repo, prune_limit: -1) end
      assert_raise ArgumentError, fn -> Config.new(repo: Repo, prune_limit: 0) end
      assert_raise ArgumentError, fn -> Config.new(repo: Repo, prune_limit: "5") end
      assert_raise ArgumentError, fn -> Config.new(repo: Repo, prune_limit: 1.0) end

      assert %Config{} = Config.new(repo: Repo, prune_limit: 5_000)
    end

    test ":queues are validated as atom, integer pairs" do
      assert_raise ArgumentError, fn -> Config.new(repo: Repo, queues: %{default: 25}) end
      assert_raise ArgumentError, fn -> Config.new(repo: Repo, queues: [{"default", 25}]) end
      assert_raise ArgumentError, fn -> Config.new(repo: Repo, queues: [default: 0]) end
      assert_raise ArgumentError, fn -> Config.new(repo: Repo, queues: [default: 3.5]) end

      assert %Config{} = Config.new(repo: Repo, queues: [default: 1])
      assert %Config{queues: []} = Config.new(repo: Repo, queues: false)
    end

    test ":rescue_after is validated as an integer" do
      assert_raise ArgumentError, fn -> Config.new(repo: Repo, rescue_after: -1) end
      assert_raise ArgumentError, fn -> Config.new(repo: Repo, rescue_after: 0) end
      assert_raise ArgumentError, fn -> Config.new(repo: Repo, rescue_after: "5") end
      assert_raise ArgumentError, fn -> Config.new(repo: Repo, rescue_after: 1.0) end

      assert %Config{} = Config.new(repo: Repo, rescue_after: 30)
    end

    test ":rescue_interval is validated as an integer" do
      assert_raise ArgumentError, fn -> Config.new(repo: Repo, rescue_interval: -1) end
      assert_raise ArgumentError, fn -> Config.new(repo: Repo, rescue_interval: 0) end
      assert_raise ArgumentError, fn -> Config.new(repo: Repo, rescue_interval: "5") end
      assert_raise ArgumentError, fn -> Config.new(repo: Repo, rescue_interval: 1.0) end

      assert %Config{} = Config.new(repo: Repo, rescue_interval: 10)
    end

    test ":shutdown_grace_period is validated as an integer" do
      assert_raise ArgumentError, fn -> Config.new(repo: Repo, shutdown_grace_period: -1) end
      assert_raise ArgumentError, fn -> Config.new(repo: Repo, shutdown_grace_period: 0) end
      assert_raise ArgumentError, fn -> Config.new(repo: Repo, shutdown_grace_period: "5") end
      assert_raise ArgumentError, fn -> Config.new(repo: Repo, shutdown_grace_period: 1.0) end

      assert %Config{} = Config.new(repo: Repo, shutdown_grace_period: 10)
    end

    test ":verbose is validated as `false` or a valid log level" do
      assert_raise ArgumentError, fn -> Config.new(repo: Repo, verbose: 1) end
      assert_raise ArgumentError, fn -> Config.new(repo: Repo, verbose: "false") end
      assert_raise ArgumentError, fn -> Config.new(repo: Repo, verbose: nil) end
      assert_raise ArgumentError, fn -> Config.new(repo: Repo, verbose: :warning) end
      assert_raise ArgumentError, fn -> Config.new(repo: Repo, verbose: true) end

      assert %Config{verbose: false} = Config.new(repo: Repo, verbose: false)
      assert %Config{verbose: :warn} = Config.new(repo: Repo, verbose: :warn)
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
end
