defmodule Oban.Notifier do
  @moduledoc false

  # The notifier has several different responsibilities and some nuanced behavior:
  #
  # On Start:
  # 1. Create a connection
  # 2. Listen for insert/signal events
  # 3. If connection fails then log the error, break the circuit, and attempt to connect later
  #
  # On Exit:
  # 1. Trip the circuit breaker
  # 2. Schedule a reconnect with backoff
  #
  # On Listen:
  # 1. Put the producer into the listeners map
  # 2. Monitor the pid so that we can clean up if the producer dies
  #
  # On Notification:
  # 1. Iterate through the listeners and forward the message

  use GenServer

  import Oban.Breaker, only: [open_circuit: 1, trip_circuit: 3]

  alias Oban.Config
  alias Postgrex.Notifications

  @type option :: {:name, module()} | {:conf, Config.t()}
  @type channel :: :gossip | :insert | :signal
  @type queue :: atom()

  @mappings %{
    gossip: "oban_gossip",
    insert: "oban_insert",
    signal: "oban_signal"
  }

  @channels Map.keys(@mappings)

  defmodule State do
    @moduledoc false

    @enforce_keys [:conf]
    defstruct [
      :conf,
      :conn,
      :name,
      circuit: :enabled,
      listeners: %{}
    ]
  end

  defmacro gossip, do: @mappings[:gossip]
  defmacro insert, do: @mappings[:insert]
  defmacro signal, do: @mappings[:signal]

  defguardp is_server(server) when is_pid(server) or is_atom(server)

  @spec start_link([option]) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)

    GenServer.start_link(__MODULE__, Map.new(opts), name: name)
  end

  @spec listen(module()) :: :ok
  def listen(server, channels \\ @channels) when is_server(server) and is_list(channels) do
    GenServer.call(server, {:listen, channels})
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
    [_prefix, channel] = String.split(prefixed_channel, ".")

    decoded = Jason.decode!(payload)

    for {pid, channels} <- state.listeners, channel in channels do
      send(pid, {:notification, channel, decoded})
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

      full_channels =
        @mappings
        |> Map.take(channels)
        |> Map.values()

      {:reply, :ok, %{state | listeners: Map.put(listeners, pid, full_channels)}}
    end
  end

  defp connect_and_listen(%State{conf: conf, conn: nil} = state) do
    case Notifications.start_link(conf.repo.config()) do
      {:ok, conn} ->
        Notifications.listen(conn, "#{conf.prefix}.#{gossip()}")
        Notifications.listen(conn, "#{conf.prefix}.#{insert()}")
        Notifications.listen(conn, "#{conf.prefix}.#{signal()}")

        %{state | conn: conn}

      {:error, error} ->
        trip_circuit(error, [], state)
    end
  end

  defp connect_and_listen(state), do: state
end
