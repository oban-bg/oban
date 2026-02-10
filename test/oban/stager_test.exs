defmodule Oban.StagerTest.ExitOnNotify do
  @moduledoc false
  @behaviour Oban.Notifier

  use GenServer

  defstruct [:conf, armed: false, listeners: %{}]

  @impl Oban.Notifier
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)

    GenServer.start_link(__MODULE__, struct!(__MODULE__, opts), name: name)
  end

  @impl Oban.Notifier
  def listen(server, channels), do: GenServer.call(server, {:listen, channels})

  @impl Oban.Notifier
  def unlisten(server, _channels), do: GenServer.call(server, :ok)

  @impl Oban.Notifier
  def notify(server, channel, payload) do
    case GenServer.call(server, :get_state) do
      {:ok, %{armed: true}} ->
        exit({:noproc, {GenServer, :call, [server, channel, payload]}})

      {:ok, %{listeners: listeners, conf: conf}} ->
        for {pid, chs} <- listeners, message <- payload, channel in chs do
          Oban.Notifier.relay(conf, [pid], channel, message)
        end

        :ok
    end
  end

  @impl GenServer
  def init(state), do: {:ok, state}

  @impl GenServer
  def handle_call(:ok, _from, state), do: {:reply, :ok, state}
  def handle_call(:arm, _from, state), do: {:reply, :ok, %{state | armed: true}}
  def handle_call(:get_state, _from, state), do: {:reply, {:ok, state}, state}

  def handle_call({:listen, channels}, {pid, _}, %{listeners: listeners} = state) do
    if Map.has_key?(listeners, pid) do
      {:reply, :ok, state}
    else
      Process.monitor(pid)

      {:reply, :ok, %{state | listeners: Map.put(listeners, pid, channels)}}
    end
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, %{state | listeners: Map.delete(state.listeners, pid)}}
  end

  def handle_info(_message, state), do: {:noreply, state}
end

defmodule Oban.StagerTest do
  use Oban.Case, async: true

  alias Oban.{Notifier, Sonar, Stager}
  alias Oban.StagerTest.ExitOnNotify
  alias Oban.TelemetryHandler

  test "descheduling jobs to make them available for execution" do
    job_1 = insert!(%{}, state: "scheduled", scheduled_at: seconds_ago(10))
    job_2 = insert!(%{}, state: "scheduled", scheduled_at: seconds_from_now(10))
    job_3 = insert!(%{}, state: "retryable")

    start_supervised_oban!(stage_interval: 5, testing: :disabled)

    with_backoff(fn ->
      assert %{state: "available"} = Repo.reload(job_1)
      assert %{state: "scheduled"} = Repo.reload(job_2)
      assert %{state: "available"} = Repo.reload(job_3)
    end)
  end

  test "emitting telemetry data for staged jobs" do
    TelemetryHandler.attach_events()

    start_supervised_oban!(stage_interval: 5, testing: :disabled)

    assert_receive {:event, :stop, %{duration: _}, %{plugin: Stager} = meta}

    assert %{staged_count: _, staged_jobs: []} = meta
  end

  test "switching to local mode without functional pubsub" do
    :telemetry_test.attach_event_handlers(self(), [[:oban, :stager, :switch]])

    [stage_interval: 5, notifier: {Oban.Notifiers.Isolated, connected: false}]
    |> start_supervised_oban!()
    |> ping_sonar()

    assert_receive {[:oban, :stager, :switch], _, %{}, %{mode: :local}}
  end

  test "switching to local mode when solitary and not the leader" do
    :telemetry_test.attach_event_handlers(self(), [[:oban, :stager, :switch]])

    opts = [
      stage_interval: 5,
      notifier: Oban.Notifiers.Isolated,
      peer: {Oban.Peers.Isolated, leader?: false}
    ]

    opts
    |> start_supervised_oban!()
    |> ping_sonar()

    assert_receive {[:oban, :stager, :switch], _, %{}, %{mode: :local}}
  end

  test "dispatching directly to registered producers in local mode" do
    name =
      start_supervised_oban!(
        stage_interval: 5,
        notifier: Oban.Notifiers.Isolated,
        peer: {Oban.Peers.Isolated, leader?: false}
      )

    ping_sonar(name)

    with {:via, _, {_, prod_name}} <- Oban.Registry.via(name, {:producer, "staging_test"}) do
      Registry.register(Oban.Registry, prod_name, nil)
    end

    assert_receive {:notification, :insert, %{"queue" => "staging_test"}}
  end

  @tag :capture_log
  test "stager survives exit from notifier during staging" do
    name =
      start_supervised_oban!(
        notifier: ExitOnNotify,
        stage_interval: :timer.minutes(60),
        testing: :disabled
      )

    stager_pid = Oban.Registry.whereis(name, Stager)
    notifier_pid = Oban.Registry.whereis(name, Notifier)

    # Ensure Sonar has completed handle_continue before proceeding.
    _ = :sys.get_state(Oban.Registry.whereis(name, Sonar))

    # Arm the notifier so the next notify call exits the caller.
    GenServer.call(notifier_pid, :arm)

    # Trigger staging. Without the try/catch in notify_queues, the exit
    # from Notifier.notify propagates and crashes the Stager.
    send(stager_pid, :stage)

    # A synchronous :sys call ensures the :stage message was fully processed.
    # If the Stager had crashed, this would raise.
    _ = :sys.get_state(stager_pid)
    assert Process.alive?(stager_pid)
  end

  defp ping_sonar(name) do
    name
    |> Oban.Registry.whereis(Oban.Sonar)
    |> send(:ping)
  end
end
