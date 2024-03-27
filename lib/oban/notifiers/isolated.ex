defmodule Oban.Notifiers.Isolated do
  @moduledoc false

  @behaviour Oban.Notifier

  use GenServer

  alias Oban.Notifier

  defstruct [:conf, connected: true, listeners: %{}]

  @impl Notifier
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)

    GenServer.start_link(__MODULE__, struct!(__MODULE__, opts), name: name)
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
    with {:ok, %{connected: true} = state} <- GenServer.call(server, :get_state) do
      for {pid, channels} <- state.listeners, message <- payload, channel in channels do
        Notifier.relay(state.conf, [pid], channel, message)
      end
    end

    :ok
  end

  @impl GenServer
  def init(state) do
    {:ok, state}
  end

  @impl GenServer
  def handle_call(:get_state, _from, state) do
    {:reply, {:ok, state}, state}
  end

  def handle_call({:listen, channels}, {pid, _}, %{listeners: listeners} = state) do
    if Map.has_key?(listeners, pid) do
      {:reply, :ok, state}
    else
      Process.monitor(pid)

      {:reply, :ok, %{state | listeners: Map.put(listeners, pid, channels)}}
    end
  end

  def handle_call({:unlisten, channels}, {pid, _}, %{listeners: listeners} = state) do
    orig_channels = Map.get(listeners, pid, [])

    listeners =
      case orig_channels -- channels do
        [] -> Map.delete(listeners, pid)
        new_channels -> Map.put(listeners, pid, new_channels)
      end

    {:reply, :ok, %{state | listeners: listeners}}
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, %{state | listeners: Map.delete(state.listeners, pid)}}
  end
end
