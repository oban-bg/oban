defmodule Oban.PostgresNotifier do
  @doc """
  Postgres Listen/Notify based Notifier

  ## Caveats

  The notifications system is built on PostgreSQL's `LISTEN/NOTIFY` functionality. Notifications
  are only delivered **after a transaction completes** and are de-duplicated before publishing.
  Most applications run Ecto in sandbox mode while testing. Sandbox mode wraps each test in a
  separate transaction which is rolled back after the test completes. That means the transaction
  is never committed, which prevents delivering any notifications.
  To test using notifications you must run Ecto without sandbox mode enabled.
  """

  @behaviour Oban.Notifier

  use GenServer

  import Oban.Breaker, only: [open_circuit: 1, trip_circuit: 3]

  alias Oban.{Config, Repo}
  alias Postgrex.Notifications

  @mappings %{
    gossip: "oban_gossip",
    insert: "oban_insert",
    signal: "oban_signal"
  }

  defmodule State do
    @moduledoc false

    @enforce_keys [:conf]
    defstruct [
      :conf,
      :conn,
      :name,
      circuit: :enabled,
      reset_timer: nil,
      listeners: %{}
    ]
  end

  @impl Oban.Notifier
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)

    GenServer.start_link(__MODULE__, Map.new(opts), name: name)
  end

  @impl Oban.Notifier
  def listen(server, channels) do
    GenServer.call(server, {:listen, channels})
  end

  @impl Oban.Notifier
  def unlisten(server, channels) do
    GenServer.call(server, {:unlisten, channels})
  end

  @impl Oban.Notifier
  def notify(server, channel, payload) do
    with %State{conf: conf} <- GenServer.call(server, :get_state) do
      channel = "#{conf.prefix}.#{@mappings[channel]}"

      Repo.query(
        conf,
        "SELECT pg_notify($1, payload) FROM json_array_elements_text($2::json) AS payload",
        [channel, payload]
      )

      :ok
    end
  end

  @impl GenServer
  def init(opts) do
    Process.flag(:trap_exit, true)

    {:ok, struct!(State, opts), {:continue, :start}}
  end

  @impl GenServer
  def handle_continue(:start, state) do
    {:noreply, connect_and_listen(state)}
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, pid, _reason}, %State{listeners: listeners} = state) do
    {:noreply, %{state | listeners: Map.delete(listeners, pid)}}
  end

  def handle_info({:notification, _, _, prefixed_channel, payload}, state) do
    full_channel =
      prefixed_channel
      |> String.split(".")
      |> List.last()

    channel = reverse_channel(full_channel)
    decoded = if any_listeners?(state.listeners, full_channel), do: Jason.decode!(payload)

    if in_scope?(decoded, state.conf) do
      for {pid, channels} <- state.listeners, full_channel in channels do
        send(pid, {:notification, channel, decoded})
      end
    end

    {:noreply, state}
  end

  def handle_info({:EXIT, _pid, error}, %State{} = state) do
    state = trip_circuit(error, [], state)

    {:noreply, %{state | conn: nil}}
  end

  def handle_info(:reset_circuit, %State{circuit: :disabled} = state) do
    state =
      state
      |> open_circuit()
      |> connect_and_listen()

    {:noreply, state}
  end

  def handle_info(_message, state) do
    {:noreply, state}
  end

  @impl GenServer
  def handle_call({:listen, channels}, {pid, _}, %State{listeners: listeners} = state) do
    if Map.has_key?(listeners, pid) do
      {:reply, :ok, state}
    else
      Process.monitor(pid)

      full_channels = to_full_channels(channels)

      {:reply, :ok, %{state | listeners: Map.put(listeners, pid, full_channels)}}
    end
  end

  def handle_call({:unlisten, channels}, {pid, _}, %State{listeners: listeners} = state) do
    orig_channels = Map.get(listeners, pid, [])

    listeners =
      case orig_channels -- to_full_channels(channels) do
        [] -> Map.delete(listeners, pid)
        new_channels -> Map.put(listeners, pid, new_channels)
      end

    {:reply, :ok, %{state | listeners: listeners}}
  end

  def handle_call(:get_state, _, state), do: {:reply, state, state}

  # Helpers

  for {atom, name} <- @mappings do
    defp reverse_channel(unquote(name)), do: unquote(atom)
  end

  defp to_full_channels(channels) do
    @mappings
    |> Map.take(channels)
    |> Map.values()
  end

  defp any_listeners?(listeners, full_channel) do
    Enum.any?(listeners, fn {_pid, channels} -> full_channel in channels end)
  end

  defp in_scope?(%{"ident" => "any"}, _conf), do: true
  defp in_scope?(%{"ident" => ident}, conf), do: Config.match_ident?(conf, ident)
  defp in_scope?(_decoded, _conf), do: true

  defp connect_and_listen(%State{conf: conf, conn: nil} = state) do
    case Notifications.start_link(Repo.config(conf)) do
      {:ok, conn} ->
        for {_, full} <- @mappings,
            do: Notifications.listen(conn, "#{conf.prefix}.#{full}")

        %{state | conn: conn}

      {:error, error} ->
        trip_circuit(error, [], state)
    end
  end

  defp connect_and_listen(state), do: state
end
