defmodule Oban.ConfigTest do
  use Oban.Case, async: true

  alias Oban.Config
  alias Oban.{Cron, Pruner}

  doctest Config

  defmodule NotRepo do
  end

  defmodule SomeRepo do
    def config, do: []
  end

  defmodule FakePlugin do
    def init(opts), do: {:ok, opts}
  end

  describe "validate/1" do
    test "legacy :circuit_backoff option is ignored" do
      assert_valid(circuit_backoff: 10)
    end

    test ":engine is validated as an engine module" do
      refute_valid(engine: nil)
      refute_valid(engine: Repo)

      assert_valid(engine: Oban.Engines.Basic)
      assert_valid(engine: Oban.Engines.Inline)
      assert_valid(engine: Oban.Engines.Lite)
    end

    test ":insert_trigger is validated as a boolean" do
      refute_valid(insert_trigger: nil)
      refute_valid(insert_trigger: 1)

      assert_valid(insert_trigger: true)
      assert_valid(insert_trigger: false)
    end

    test ":repo accepts log and dynamic_repo options in the tuple form" do
      refute_valid(repo: {SomeRepo, log: 1})
      refute_valid(repo: {SomeRepo, log: :nothing})
      refute_valid(repo: {SomeRepo, log: true})
      refute_valid(repo: {SomeRepo, dynamic_repo: :nope})

      assert_valid(repo: {SomeRepo, log: false})
      assert_valid(repo: {SomeRepo, log: :alert})
      assert_valid(repo: {SomeRepo, log: :debug})
      assert_valid(repo: {SomeRepo, dynamic_repo: fn -> SomeRepo end})
    end

    test "top-level :log and :get_dynamic_repo remain valid for backward compatibility" do
      refute_valid(log: :nothing)

      assert_valid(log: false)
      assert_valid(log: :debug)
      assert_valid(get_dynamic_repo: fn -> SomeRepo end)
    end

    test ":notifier is validated as a notifier module" do
      refute_valid(notifier: nil)
      refute_valid(notifier: Repo)
      refute_valid(notifier: {Oban.Notifiers.Postgres, true})

      assert_valid(notifier: Oban.Notifiers.Postgres)
      assert_valid(notifier: {Oban.Notifiers.Postgres, [some: :opt]})
    end

    test ":node is validated as a coerced binary" do
      refute_valid(node: nil)
      refute_valid(node: ~c"")
      refute_valid(node: "")
      refute_valid(node: "  ")
      refute_valid(node: MyNode)

      assert_valid(node: "MyNode")
    end

    test ":peer is validated as false or a peer module" do
      refute_valid(peer: Fake)
      refute_valid(peer: {Oban.Peers.Global, false})

      assert_valid(peer: false)
      assert_valid(peer: Oban.Peers.Global)
      assert_valid(peer: Oban.Peers.Database)
      assert_valid(peer: {Oban.Peers.Database, [some: :opt]})
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
      refute_valid(prefix: true)

      assert_valid(prefix: false)
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

    test ":queues are validated as a plugin when set to a module" do
      refute_valid(queues: {NotReal, queues: [default: 1]})
      refute_valid(queues: {SomeRepo, queues: [default: 1]})
      refute_valid(queues: {FakePlugin, %{default: 1}})

      assert_valid(queues: {FakePlugin, queues: [default: 1]})
      assert_valid(queues: {FakePlugin, []})
    end

    test ":repo is validated as a repo-like module" do
      refute_valid(repo: NotReal)
      refute_valid(repo: NotRepo)

      assert_valid(repo: SomeRepo)
    end

    test ":shutdown_grace_period is validated as an integer" do
      refute_valid(shutdown_grace_period: -1)
      refute_valid(shutdown_grace_period: "5")
      refute_valid(shutdown_grace_period: 1.0)

      assert_valid(shutdown_grace_period: 0)
      assert_valid(shutdown_grace_period: 10)
    end

    test ":stager is validated as false or a module with options" do
      refute_valid(stager: nil)
      refute_valid(stager: NotReal)
      refute_valid(stager: [interval: :none])
      refute_valid(stager: [limit: 0])
      refute_valid(stager: [unknown: true])
      refute_valid(stage_interval: :none)

      assert_valid(stager: false)
      assert_valid(stager: [interval: 500])
      assert_valid(stager: [interval: :infinity])
      assert_valid(stager: [interval: 500, limit: 1_000])
      assert_valid(stager: {FakePlugin, interval: 500})
      assert_valid(stage_interval: 500)
    end

    test ":testing is validated as a boolean" do
      refute_valid(testing: :ok)
      refute_valid(testing: true)

      assert_valid(testing: :inline)
      assert_valid(testing: :manual)
      assert_valid(testing: :disabled)
    end

    test "alternatives are suggested for unknown options when they match" do
      assert {:error, "unknown option :queue, did you mean :queues?"} = validate(queue: false)
      assert {:error, "unknown option :nam, did you mean :name?"} = validate(nam: :web)
    end

    test "a plugin configured more than once is rejected" do
      refute_valid(plugins: [Pruner, {Pruner, max_age: 60}])
      refute_valid(pruner: [max_age: 60], plugins: [Pruner])
      refute_valid(cron: [crontab: [{"* * * * *", Worker}]], plugins: [Cron])
      refute_valid(cron: [crontab: []], crontab: [{"* * * * *", Worker}])

      assert_valid(pruner: [max_age: 60], plugins: [Cron])
      assert_valid(plugins: [Pruner, Cron])
    end

    test "services are validated as plugins" do
      refute_valid(pruner: NotReal)
      refute_valid(pruner: {NotReal, []})
      refute_valid(lifeline: [rescue_after: 0])

      assert_valid(pruner: Pruner)
      assert_valid(pruner: {Pruner, max_age: 60})
      assert_valid(pruner: false)
    end

    test "services are accepted while plugins are disabled" do
      assert_valid(plugins: false, cron: [crontab: []])
      assert_valid(plugins: false, pruner: [max_age: 60])
      assert_valid(plugins: false, queues: [default: 1])
      assert_valid(plugins: false, queues: {FakePlugin, queues: [default: 1]})
    end

    test "duplicated values are rejected" do
      assert {:error, "found duplicate options: [:peer]"} ==
               validate(peer: false, peer: Oban.Peers.Postgres)

      assert {:error, "found duplicate options: [:peer, :plugins]"} ==
               validate(
                 peer: false,
                 peer: Oban.Peers.Postgres,
                 plugins: [Pruner],
                 plugins: false
               )
    end
  end

  describe "new/1" do
    test ":name defaults to Oban" do
      assert %Config{name: Oban} = conf(queues: [])
    end

    test ":notifier translates to the correct postgres module" do
      assert %Config{notifier: {Oban.Notifiers.Postgres, []}} =
               conf(notifier: Oban.PostgresNotifier)
    end

    test ":engine translates to the correct basic module" do
      assert %Config{engine: Oban.Engines.Basic} = conf(engine: Oban.Queue.BasicEngine)
    end

    test ":queues convert to an empty list when set to false" do
      assert %Config{queues: []} = conf(queues: false)
    end

    test ":testing in :manual mode disables queues, peer, and plugins" do
      assert conf = conf(queues: [alpha: 1], plugins: [Pruner], testing: :manual)

      assert %{queues: [], plugins: []} = conf
      assert %{peer: {Oban.Peers.Isolated, [leader?: false]}, stager: false} = conf
    end

    test "normalizing plugins as a module options tuple" do
      assert %Config{plugins: plugins} = conf(plugins: [Cron, {Pruner, []}])

      for plugin <- plugins do
        assert {module, opts} = plugin
        assert is_atom(module)
        assert is_list(opts)
      end
    end

    test "translating deprecated crontab/timezone config into plugin usage" do
      assert has_plugin?(Cron, timezone: "America/Chicago", crontab: [{"* * * * *", Worker}])
      assert has_plugin?(Cron, crontab: [{"* * * * *", Worker}])
      assert has_plugin?(Cron, plugins: [Pruner], crontab: [{"* * * * *", Worker}])

      refute has_plugin?(Cron, timezone: "America/Chicago")
      refute has_plugin?(Cron, plugins: false, crontab: [{"* * * * *", Worker}])
    end

    test "translating legacy interval config into stager options" do
      assert %{stager: {Oban.Stager, []}} = conf([])
      assert %{stager: {Oban.Stager, [interval: 2_000]}} = conf(poll_interval: 2_000)
      assert %{stager: {Oban.Stager, [interval: 2_000]}} = conf(stage_interval: 2_000)
      assert %{stager: {Oban.Stager, []}} = conf(plugins: [Oban.Stager])

      assert %{stager: {Oban.Stager, [interval: 1_000]}} =
               conf(poll_interval: :infinity, stage_interval: 1_000)

      assert %{stager: {Oban.Stager, [interval: 2_000]}, plugins: []} =
               conf(plugins: [{Oban.Stager, interval: 2_000}])

      assert %{stager: {Oban.Stager, [interval: 500]}} =
               conf(stage_interval: 2_000, stager: [interval: 500])
    end

    test "normalizing stager values into module and option tuples" do
      assert %{stager: {Oban.Stager, [interval: 500]}} = conf(stager: [interval: 500])
      assert %{stager: {Oban.Stager, [limit: 1_000]}} = conf(stager: [limit: 1_000])
      assert %{stager: {FakePlugin, []}} = conf(stager: FakePlugin)
      assert %{stager: {FakePlugin, [interval: 500]}} = conf(stager: {FakePlugin, interval: 500})
      assert %{stager: false} = conf(stager: false)
    end

    test "translating top-level service keys into plugin usage" do
      assert has_plugin?(Cron, cron: [crontab: [{"* * * * *", Worker}]])
      assert has_plugin?(Pruner, pruner: [max_age: 60])
      assert has_plugin?(Oban.Lifeline, lifeline: [])
      assert has_plugin?(Oban.Lifeline, lifeline: [rescue_after: 60_000])
      assert has_plugin?(Oban.Lifeline, lifeline: Oban.Lifeline)

      refute has_plugin?(Pruner, pruner: false)
      refute has_plugin?(Pruner, [])
    end

    test "pinning an explicit module through a service key" do
      assert %Config{plugins: plugins} = conf(pruner: {FakePlugin, max_age: 60})

      assert {FakePlugin, [max_age: 60]} in plugins

      assert %Config{plugins: plugins} = conf(pruner: FakePlugin)

      assert {FakePlugin, []} in plugins
    end

    test "passing service key options through to the plugin" do
      assert %Config{plugins: plugins} = conf(pruner: [max_age: 60])

      assert {Pruner, [max_age: 60]} in plugins
    end

    test "translating a :queues module into plugin usage" do
      assert %Config{queues: [], plugins: plugins} =
               conf(queues: {FakePlugin, queues: [default: 1]})

      assert {FakePlugin, [queues: [default: 1]]} in plugins
    end

    test "translating legacy plugin modules into their renamed version" do
      assert %Config{plugins: [{Oban.Pruner, []}]} = conf(plugins: [Oban.Plugins.Pruner])

      assert %Config{plugins: [{Oban.Cron, [crontab: []]}]} =
               conf(plugins: [{Oban.Plugins.Cron, crontab: []}])

      assert has_plugin?(Oban.Lifeline, plugins: [Oban.Plugins.Lifeline])
      assert has_plugin?(Oban.Reindexer, plugins: [Oban.Plugins.Reindexer])
    end

    test "disabling plugins also disables top-level services" do
      refute has_plugin?(Pruner, plugins: false, pruner: [max_age: 60])
      refute has_plugin?(Cron, plugins: false, cron: [crontab: []])
    end

    test "disabling plugins doesn't disable queues" do
      assert %Config{queues: [alpha: [limit: 1]]} = conf(plugins: false, queues: [alpha: 1])
    end

    test ":testing in :manual mode suppresses top-level services" do
      conf = conf(pruner: [max_age: 60], cron: [crontab: []], testing: :manual)
      assert %{plugins: [], stager: false} = conf

      conf = conf(queues: [default: 1], testing: :manual)
      assert %{plugins: [], queues: []} = conf
    end

    test "translating :peer false to the disabled module" do
      assert %Config{peer: {Oban.Peers.Isolated, [leader?: false]}} = conf(peer: false)
      assert %Config{peer: {Oban.Peers.Isolated, [leader?: false]}} = conf(plugins: false)

      assert %Config{peer: {Oban.Peers.Isolated, [leader?: false]}} =
               conf(peer: Oban.Peers.Global, plugins: false)
    end

    test "translating the :peer from Postgres to Database" do
      assert %Config{peer: {Oban.Peers.Database, []}} = conf(peer: Oban.Peers.Postgres)

      assert %Config{peer: {Oban.Peers.Database, [interval: 10]}} =
               conf(peer: {Oban.Peers.Postgres, interval: 10})
    end

    test "setting sane defaults for the Lite engine" do
      conf = conf(engine: Oban.Engines.Lite)

      refute conf.prefix
      assert {Oban.Notifiers.PG, []} = conf.notifier
      assert {Oban.Peers.Isolated, []} = conf.peer
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
    assert {:error, _reason} = validate(opts)
  end

  defp assert_valid(opts) do
    assert :ok = validate(opts)
  end

  defp conf(opts) do
    opts
    |> Keyword.put_new(:repo, Repo)
    |> Config.new()
  end

  defp validate(opts) do
    opts
    |> Keyword.put_new(:repo, Repo)
    |> Config.validate()
  end

  def has_plugin?(plugin, opts) do
    plugins =
      opts
      |> conf()
      |> Map.fetch!(:plugins)
      |> Enum.map(fn {module, _opts} -> module end)

    plugin in plugins
  end
end
