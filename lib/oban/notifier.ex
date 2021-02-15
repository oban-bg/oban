defmodule Oban.Notifier do
  @moduledoc """
  The `Notifier` coordinates listening for and publishing notifications for events in predefined
  channels.

  Every Oban supervision tree contains a notifier process, registered as `Oban.Notifier`, which
  itself maintains a single connection with an app's database. All incoming notifications are
  relayed through that connection to other processes.

  ## Channels

  The notifier recognizes three predefined channels, each with a distinct responsibility:

  * `gossip` — arbitrary communication between nodes or jobs are sent on the `gossip` channel
  * `insert` — as jobs are inserted into the database an event is published on the `insert`
    channel. Processes such as queue producers use this as a signal to dispatch new jobs.
  * `signal` — instructions to take action, such as scale a queue or kill a running job, are sent
    through the `signal` channel.

  The `insert` and `signal` channels are primarily for internal use. Use the `gossip` channel to
  send notifications between jobs or processes in your application.

  ## Caveats

  The notifications system is built on PostgreSQL's `LISTEN/NOTIFY` functionality. Notifications
  are only delivered **after a transaction completes** and are de-duplicated before publishing.

  Most applications run Ecto in sandbox mode while testing. Sandbox mode wraps each test in a
  separate transaction which is rolled back after the test completes. That means the transaction
  is never committed, which prevents delivering any notifications.

  To test using notifications you must run Ecto without sandbox mode enabled.

  ## Examples

  Broadcasting after a job is completed:

      defmodule MyApp.Worker do
        use Oban.Worker

        @impl Oban.Worker
        def perform(job) do
          :ok = MyApp.do_work(job.args)

          Oban.Notifier.notify(Oban.config(), :gossip, %{complete: job.id})

          :ok
        end
      end

  Listening for job complete events from another process:

      def insert_and_listen(args) do
        {:ok, job} =
          args
          |> MyApp.Worker.new()
          |> Oban.insert()

        receive do
          {:notification, :gossip, %{"complete" => ^job.id}} ->
            IO.puts("Other job complete!")
        after
          30_000 ->
            IO.puts("Other job didn't finish in 30 seconds!")
        end
      end
  """

  use GenServer

  import Oban.Breaker, only: [open_circuit: 1, trip_circuit: 3]

  alias Oban.{Config, Registry, Repo}
  alias Postgrex.Notifications

  @type option :: {:name, module()} | {:conf, Config.t()}
  @type channel :: :gossip | :insert | :signal

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
      reset_timer: nil,
      listeners: %{}
    ]
  end

  defguardp is_channel(channel) when channel in @channels

  @doc false
  @spec start_link([option]) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)

    GenServer.start_link(__MODULE__, Map.new(opts), name: name)
  end

  @doc """
  Register the current process to receive relayed messages for the provided channels.

  All messages are received as `JSON` and decoded _before_ they are relayed to registered
  processes. Each registered process receives a three element notification tuple in the following
  format:

      {:notification, channel :: channel(), decoded :: map()}

  ## Example

  Register to listen for all `:gossip` channel messages:

      Oban.Notifier.listen([:gossip])

  Listen for messages on all channels:

      Oban.Notifier.listen([:gossip, :insert, :signal])

  Listen for messages when using a custom Oban name:

      Oban.Notifier.listen(MyApp.Oban, [:gossip, :insert, :signal])
  """
  @spec listen(GenServer.server(), channels :: list(channel())) :: :ok
  def listen(server \\ Oban, channels)

  def listen(pid, channels) when is_pid(pid) and is_list(channels) do
    :ok = validate_channels!(channels)

    GenServer.call(pid, {:listen, channels})
  end

  def listen(oban_name, channels) when is_list(channels) do
    oban_name
    |> Registry.whereis(__MODULE__)
    |> listen(channels)
  end

  @doc """
  Broadcast a notification to listeners on all nodes.

  Notifications are scoped to the configured `prefix`. For example, if there are instances running
  with the `public` and `private` prefixes, a notification published in the `public` prefix won't
  be picked up by processes listening with the `private` prefix.

  ## Example

  Broadcast a gossip message:

      Oban.Notifier.notify(Oban.config(), :gossip, %{message: "hi!"})
  """
  @spec notify(Config.t(), channel :: channel(), payload :: map()) :: :ok
  def notify(%Config{} = conf, channel, %{} = payload) when is_channel(channel) do
    channel = "#{conf.prefix}.#{@mappings[channel]}"
    payload = Jason.encode!(payload)

    {:ok, _} = Repo.query(conf, "SELECT pg_notify($1, $2)", [channel, payload])

    :ok
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

      full_channels =
        @mappings
        |> Map.take(channels)
        |> Map.values()

      {:reply, :ok, %{state | listeners: Map.put(listeners, pid, full_channels)}}
    end
  end

  # Helpers

  for {atom, name} <- @mappings do
    defp reverse_channel(unquote(name)), do: unquote(atom)
  end

  defp validate_channels!([]), do: :ok
  defp validate_channels!([head | tail]) when is_channel(head), do: validate_channels!(tail)
  defp validate_channels!([head | _]), do: raise(ArgumentError, "unexpected channel: #{head}")

  defp any_listeners?(listeners, full_channel) do
    Enum.any?(listeners, fn {_pid, channels} -> full_channel in channels end)
  end

  defp in_scope?(%{"ident" => "any"}, _conf), do: true
  defp in_scope?(%{"ident" => ident}, conf), do: Config.match_ident?(conf, ident)
  defp in_scope?(_decoded, _conf), do: true

  defp connect_and_listen(%State{conf: conf, conn: nil} = state) do
    case Notifications.start_link(Repo.config(conf)) do
      {:ok, conn} ->
        for {_, full} <- @mappings, do: Notifications.listen(conn, "#{conf.prefix}.#{full}")

        %{state | conn: conn}

      {:error, error} ->
        trip_circuit(error, [], state)
    end
  end

  defp connect_and_listen(state), do: state
end
