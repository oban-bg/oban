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

  ## Migrating from `Oban.Notifiers.Postgres`

  After switching from `Oban.Notifiers.Postgres`, you may remove the unused `oban_notify` trigger.
  Use the following migration to drop the trigger while retaining the `oban_jobs_notify` function:

  ```elixir
  defmodule MyApp.Repo.Migrations.DropObanJobsNotifyTrigger do
    use Ecto.Migration

    def change do
      execute(
        "DROP TRIGGER IF EXISTS oban_notify ON public.oban_jobs",
        "CREATE TRIGGER oban_notify AFTER INSERT ON public.oban_jobs FOR EACH ROW EXECUTE PROCEDURE public.oban_jobs_notify()"
      )
    end
  end
  ```

  [de]: https://elixir-lang.org/getting-started/mix-otp/distributed-tasks.html#our-first-distributed-code
  """

  @behaviour Oban.Notifier

  use GenServer

  alias Oban.Notifier

  defmodule State do
    @moduledoc false

    defstruct [:conf, :name, listeners: %{}]
  end

  @impl Notifier
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)

    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl Notifier
  def listen(server, channels) do
    GenServer.call(server, {:listen, channels})
  end

  @impl Notifier
  def unlisten(server, channels) do
    GenServer.call(server, {:unlisten, channels})
  end

  @impl Notifier
  def notify(server, channel, payload) do
    with %State{conf: conf} <- get_state(server) do
      pids = :pg.get_members(__MODULE__, conf.prefix)

      for pid <- pids, message <- payload_to_messages(channel, payload) do
        send(pid, message)
      end

      :ok
    end
  end

  @impl GenServer
  def init(opts) do
    state = struct!(State, opts)

    put_state(state)

    :pg.start_link(__MODULE__)
    :pg.join(__MODULE__, state.conf.prefix, self())

    {:ok, state}
  end

  defp put_state(state) do
    Registry.update_value(Oban.Registry, {state.conf.name, Oban.Notifier}, fn _ -> state end)
  end

  defp get_state(server) do
    [name] = Registry.keys(Oban.Registry, server)

    case Oban.Registry.lookup(name) do
      {_pid, state} -> state
      nil -> :error
    end
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

  @impl GenServer
  def handle_info({:notification, channel, payload}, %State{} = state) do
    listeners = for {pid, channels} <- state.listeners, channel in channels, do: pid

    Notifier.relay(state.conf, listeners, channel, payload)

    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, %{state | listeners: Map.delete(state.listeners, pid)}}
  end

  def handle_info(_message, state) do
    {:noreply, state}
  end

  ## Message Helpers

  defp payload_to_messages(channel, payload) do
    Enum.map(payload, &{:notification, channel, &1})
  end
end
