defmodule Oban.Notifiers.Isolated do
  @moduledoc false

  @behaviour Oban.Notifier

  use GenServer

  alias Oban.Notifier

  defstruct [:conf, connected: true]

  @impl Notifier
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)

    GenServer.start_link(__MODULE__, struct!(__MODULE__, opts), name: name)
  end

  @impl Notifier
  def listen(_server, _channels), do: :ok

  @impl Notifier
  def unlisten(_server, _channels), do: :ok

  @impl Notifier
  def notify(server, channel, payload) do
    with {:ok, %{connected: true} = state} <- GenServer.call(server, :get_state) do
      for message <- payload, do: Notifier.relay(state.conf, channel, message)
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
end
