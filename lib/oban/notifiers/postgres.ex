defmodule Oban.Notifiers.Postgres do
  @moduledoc """
  A Postgres Listen/Notify based Notifier.

  ## Usage

  Specify the `Postgres` notifier in your Oban configuration:

      config :my_app, Oban,
        notifier: Oban.Notifiers.Postgres

  ## Caveats

  The notifications system is built on PostgreSQL's `LISTEN/NOTIFY` functionality. Notifications
  are only delivered **after a transaction completes** and are de-duplicated before publishing.
  Typically, applications run Ecto in sandbox mode while testing, but sandbox mode wraps each test
  in a separate transaction that's rolled back after the test completes. That means the
  transaction is never committed, which prevents delivering any notifications.

  To test using notifications you must run Ecto without sandbox mode enabled, or use
  `Oban.Notifiers.PG` instead.
  """

  @behaviour Postgrex.SimpleConnection

  alias Oban.{Config, Repo}
  alias Postgrex.SimpleConnection, as: Simple

  @mappings %{
    gossip: "oban_gossip",
    insert: "oban_insert",
    leader: "oban_leader",
    signal: "oban_signal"
  }

  defmodule State do
    @moduledoc false

    @enforce_keys [:conf]
    defstruct [
      :conf,
      :from,
      :key,
      channels: %{},
      connected?: false,
      listeners: %{}
    ]
  end

  @doc """
  Start the notifier.
  """
  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    conf = Keyword.fetch!(opts, :conf)

    call_opts = [conf: conf]

    conn_opts =
      conf
      |> Repo.config()
      |> Keyword.put(:name, name)
      |> Keyword.put_new(:auto_reconnect, true)
      |> Keyword.put_new(:sync_connect, false)

    Simple.start_link(__MODULE__, call_opts, conn_opts)
  end

  @doc """
  Register current process to receive messages from some channels
  """
  @spec listen(GenServer.server(), channels :: list(Oban.Notifier.channel())) :: :ok
  def listen(server, channels) do
    Simple.call(server, {:listen, channels})
  end

  @doc """
  Unregister current process from channels
  """
  @spec unlisten(GenServer.server(), channels :: list(Oban.Notifier.channel())) :: :ok
  def unlisten(server, channels) do
    Simple.call(server, {:unlisten, channels})
  end

  ## Server Callbacks

  @impl Simple
  def init(opts) do
    {:ok, struct!(State, opts)}
  end

  @impl Simple
  def notify(server, channel, payload) when channel in [:gossip, :insert, :leader, :signal] do
    with %State{conf: conf} <- Simple.call(server, :get_state) do
      full_channel = Map.fetch!(@mappings, channel)

      Repo.query(
        conf,
        "SELECT pg_notify($1, payload) FROM json_array_elements_text($2::json) AS payload",
        ["#{conf.prefix}.#{full_channel}", payload]
      )

      :ok
    end
  end

  def notify(full_channel, payload, %State{} = state) when is_binary(full_channel) do
    decoded = Jason.decode!(payload)

    if in_scope?(decoded, state.conf) do
      channel = reverse_channel(full_channel)

      for pid <- Map.get(state.channels, full_channel, []) do
        send(pid, {:notification, channel, decoded})
      end
    end

    :ok
  end

  @impl Simple
  def handle_connect(%State{channels: channels} = state) do
    state = %{state | connected?: true}

    if map_size(channels) > 0 do
      parts =
        channels
        |> Map.keys()
        |> Enum.map_join("\n", &~s(LISTEN "#{&1}";))

      query = "DO $$BEGIN #{parts} END$$"

      {:query, query, state}
    else
      {:noreply, state}
    end
  end

  @impl Simple
  def handle_disconnect(%State{} = state) do
    {:noreply, %{state | connected?: false}}
  end

  @impl Simple
  def handle_call(:get_state, from, %State{} = state) do
    Simple.reply(from, state)

    {:noreply, state}
  end

  def handle_call({:listen, channels}, {pid, _} = from, %State{} = state) do
    channels = to_full_channels(state.conf, channels)
    new_channels = channels -- Map.keys(state.channels)

    state =
      state
      |> put_listener(pid, channels)
      |> put_channels(pid, channels)

    if state.connected? and Enum.any?(new_channels) do
      parts = Enum.map_join(new_channels, " \n", &~s(LISTEN "#{&1}";))
      query = "DO $$BEGIN #{parts} END$$"

      {:query, query, %{state | from: from}}
    else
      Simple.reply(from, :ok)

      {:noreply, state}
    end
  end

  def handle_call({:unlisten, channels}, {pid, _} = from, %State{} = state) do
    channels = to_full_channels(state.conf, channels)

    state =
      state
      |> del_listener(pid, channels)
      |> del_channels(pid, channels)

    del_channels = channels -- Map.keys(state.channels)

    if state.connected? and Enum.any?(del_channels) do
      parts = Enum.map_join(del_channels, " \n", &~s(UNLISTEN "#{&1}";))
      query = "DO $$BEGIN #{parts} END$$"

      {:query, query, %{state | from: from}}
    else
      Simple.reply(from, :ok)

      {:noreply, state}
    end
  end

  @impl Simple
  def handle_info({:DOWN, _ref, :process, pid, _reason}, %State{} = state) do
    case Map.pop(state.listeners, pid) do
      {{_ref, channel_set}, listeners} ->
        state =
          state
          |> Map.put(:listeners, listeners)
          |> del_channels(pid, MapSet.to_list(channel_set))

        {:noreply, state}

      {nil, _listeners} ->
        {:noreply, state}
    end
  end

  def handle_info(_message, state) do
    {:noreply, state}
  end

  @impl Simple
  def handle_result(_results, %State{from: from} = state) do
    from && Simple.reply(from, :ok)

    {:noreply, %{state | from: nil}}
  end

  ## Channel Helpers

  defp to_full_channels(%Config{prefix: prefix}, channels) do
    @mappings
    |> Map.take(channels)
    |> Map.values()
    |> Enum.map(&Enum.join([prefix, &1], "."))
  end

  defp reverse_channel(full_channel) do
    [_prefix, "oban_" <> shortcut] = String.split(full_channel, ".", parts: 2)

    String.to_existing_atom(shortcut)
  end

  defp in_scope?(%{"ident" => "any"}, _conf), do: true
  defp in_scope?(%{"ident" => ident}, conf), do: Config.match_ident?(conf, ident)
  defp in_scope?(_decoded, _conf), do: true

  ## Listener Helpers

  defp put_listener(%{listeners: listeners} = state, pid, channels) do
    new_set = MapSet.new(channels)

    listeners =
      case Map.get(listeners, pid) do
        {ref, old_set} ->
          Map.replace!(listeners, pid, {ref, MapSet.union(old_set, new_set)})

        nil ->
          ref = Process.monitor(pid)

          Map.put(listeners, pid, {ref, new_set})
      end

    %{state | listeners: listeners}
  end

  defp put_channels(state, pid, channels) do
    listener_channels =
      for channel <- channels, reduce: state.channels do
        acc -> Map.update(acc, channel, [pid], &[pid | &1])
      end

    %{state | channels: listener_channels}
  end

  defp del_listener(%{listeners: listeners} = state, pid, channels) do
    new_set = MapSet.new(channels)

    listeners =
      case Map.get(listeners, pid) do
        {ref, old_set} ->
          del_set = MapSet.difference(old_set, new_set)

          if MapSet.size(del_set) == 0 do
            Process.demonitor(ref)

            Map.delete(listeners, pid)
          else
            Map.replace!(listeners, pid, {ref, del_set})
          end

        nil ->
          listeners
      end

    %{state | listeners: listeners}
  end

  defp del_channels(state, pid, channels) do
    listener_channels =
      for channel <- channels, reduce: state.channels do
        acc ->
          acc = Map.update(acc, channel, [], &List.delete(&1, pid))

          if Enum.empty?(acc[channel]), do: Map.delete(acc, channel), else: acc
      end

    %{state | channels: listener_channels}
  end
end
