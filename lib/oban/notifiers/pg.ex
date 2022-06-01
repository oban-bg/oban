defmodule Oban.Notifiers.PG do
  @moduledoc """
  A PG/PG2 based notifier implementation that runs with Distributed Erlang.

  Out of the box, Oban uses PostgreSQL's `LISTEN/NOTIFY` for PubSub. For most applications, that
  is fine, but Postgres-based PubSub isn't sufficient in some circumstances. In particular,
  Postgres notifications won't work when your application connects through PGbouncer in
  _transaction_ or _statement_ mode.

  _Note: You must be using [Distributed Erlang][de] to use the PG notifier._

  ## Usage

  Specify the `PG` notifier in your Oban configuration:

  ```elixir
  config :my_app, Oban,
    notifier: Oban.Notifiers.PG,
    ...
  ```

  ## Implementation Notes

  * The notifier will use `pg` if available (OTP 23+) or fall back to `pg2` for
    older OTP releases.

  * Like the Postgres implementation, notifications are namespaced by `prefix`.

  * For compatibility, message payloads are always serialized to JSON before
    broadcast and deserialized before relay to local processes.

  [de]: https://elixir-lang.org/getting-started/mix-otp/distributed-tasks.html#our-first-distributed-code
  """

  @behaviour Oban.Notifier

  use GenServer

  alias Oban.Config

  defmodule State do
    @moduledoc false

    defstruct [:conf, :name, listeners: %{}]
  end

  @impl Oban.Notifier
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)

    GenServer.start_link(__MODULE__, opts, name: name)
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
    with %State{} = state <- GenServer.call(server, :get_state),
         [_ | _] = pids <- members(state.conf.prefix) do
      for pid <- pids, message <- payload_to_messages(channel, payload) do
        send(pid, message)
      end

      :ok
    end
  end

  @impl GenServer
  def init(opts) do
    state = struct!(State, opts)

    start_pg()

    :ok = join(state.conf.prefix)

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:listen, channels}, {pid, _}, %State{listeners: listeners} = state) do
    if Map.has_key?(listeners, pid) do
      {:reply, :ok, state}
    else
      Process.monitor(pid)

      {:reply, :ok, %{state | listeners: Map.put(listeners, pid, channels)}}
    end
  end

  def handle_call({:unlisten, channels}, {pid, _}, %State{listeners: listeners} = state) do
    orig_channels = Map.get(listeners, pid, [])

    listeners =
      case orig_channels -- channels do
        [] -> Map.delete(listeners, pid)
        new_channels -> Map.put(listeners, pid, new_channels)
      end

    {:reply, :ok, %{state | listeners: listeners}}
  end

  def handle_call(:get_state, _from, state), do: {:reply, state, state}

  @impl GenServer
  def handle_info({:notification, channel, payload}, %State{} = state) do
    decoded = Jason.decode!(payload)

    if in_scope?(decoded, state.conf) do
      for {pid, channels} <- state.listeners, channel in channels do
        send(pid, {:notification, channel, decoded})
      end
    end

    {:noreply, state}
  end

  def handle_info(_message, state) do
    {:noreply, state}
  end

  ## PG Helpers

  if Code.ensure_loaded?(:pg) do
    defp start_pg do
      :pg.start_link(__MODULE__)
    end

    defp members(prefix) do
      :pg.get_members(__MODULE__, prefix)
    end

    defp join(prefix) do
      :ok = :pg.join(__MODULE__, prefix, self())
    end
  else
    defp start_pg, do: :ok

    defp members(prefix) do
      :pg2.get_members(namespace(prefix))
    end

    defp join(prefix) do
      namespace = namespace(prefix)

      :ok = :pg2.create(namespace)
      :ok = :pg2.join(namespace, self())
    end

    defp namespace(prefix), do: {:oban, prefix}
  end

  ## Message Helpers

  defp payload_to_messages(channel, payload) do
    Enum.map(payload, &{:notification, channel, &1})
  end

  defp in_scope?(%{"ident" => "any"}, _conf), do: true
  defp in_scope?(%{"ident" => ident}, conf), do: Config.match_ident?(conf, ident)
  defp in_scope?(_payload, _conf), do: true
end
