defmodule Oban.Plugins.GossipTest do
  use Oban.Case, async: true

  alias Oban.Plugins.Gossip
  alias Oban.{Notifier, Registry, TelemetryHandler}

  defmodule SlowFakeProducer do
    @moduledoc false

    use GenServer

    def start_link(opts) do
      GenServer.start_link(__MODULE__, [], name: opts[:name])
    end

    @impl GenServer
    def init(_), do: {:ok, []}

    @impl GenServer
    def handle_call(:check, _, _) do
      Process.sleep(100)

      {:reply, :ok, []}
    end
  end

  describe "validate/1" do
    test "validating numerical values" do
      assert {:error, _} = Gossip.validate(interval: nil)
      assert {:error, _} = Gossip.validate(interval: 0)

      assert :ok = Gossip.validate(interval: 1)
      assert :ok = Gossip.validate(interval: :timer.seconds(30))
    end
  end

  describe "integration" do
    test "queue producers periodically emit check meta as gossip" do
      name =
        start_supervised_oban!(
          plugins: [{Gossip, interval: 10}],
          queues: [alpha: 2, omega: 3]
        )

      :ok = Notifier.listen(name, [:gossip])

      assert_receive {:notification, :gossip, %{"queue" => "alpha", "limit" => 2}}
      assert_receive {:notification, :gossip, %{"queue" => "omega", "limit" => 3}}
    end

    test "telemetry events include plugin meta with gossip counts" do
      TelemetryHandler.attach_events()

      start_supervised_oban!(plugins: [{Gossip, interval: 10}])

      assert_receive {:event, :start, %{system_time: _}, %{conf: _, plugin: Gossip}}
      assert_receive {:event, :stop, %{duration: _}, %{conf: _, plugin: Gossip, gossip_count: 0}}
    end

    test "slow producer calls don't crash gossip checks" do
      name = start_supervised_oban!(plugins: [{Gossip, interval: 10}])

      prod_name = Registry.via(name, {:producer, :slow_fake})
      start_supervised!({SlowFakeProducer, name: prod_name})

      refute_receive {:notification, :gossip, _}
    end
  end
end
