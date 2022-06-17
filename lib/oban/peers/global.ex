defmodule Oban.Peers.Global do
  @moduledoc """
  A cluster based peer that coordinates through a distributed registry.

  Leadership is coordinated through global locks. It requires a functional distributed Erlang
  cluster, without one global plugins (Cron, Lifeline, Stager, etc.) will not function correctly.

  ## Usage

  Specify the `Global` peer in your Oban configuration.

      config :my_app, Oban,
        peer: Oban.Peers.Global,
        ...
  """

  @behaviour Oban.Peer

  use GenServer

  alias Oban.Backoff

  defmodule State do
    @moduledoc false

    defstruct [
      :conf,
      :name,
      :timer,
      interval: :timer.seconds(30),
      leader?: false
    ]
  end

  @impl Oban.Peer
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  @impl Oban.Peer
  def leader?(pid, timeout \\ 5_000) do
    GenServer.call(pid, :leader?, timeout)
  end

  @impl GenServer
  def init(opts) do
    Process.flag(:trap_exit, true)

    {:ok, struct!(State, opts), {:continue, :start}}
  end

  @impl GenServer
  def terminate(_reason, %State{timer: timer} = state) do
    if is_reference(timer), do: Process.cancel_timer(timer)
    if state.leader?, do: :global.del_lock(key(state), nodes())

    :ok
  end

  @impl GenServer
  def handle_continue(:start, %State{} = state) do
    handle_info(:election, state)
  end

  @impl GenServer
  def handle_call(:leader?, _from, %State{} = state) do
    {:reply, state.leader?, state}
  end

  @impl GenServer
  def handle_info(:election, %State{} = state) do
    locked? = :global.set_lock(key(state), nodes(), 0)

    {:noreply, schedule_election(%{state | leader?: locked?})}
  end

  defp schedule_election(%State{interval: interval} = state) do
    time = Backoff.jitter(interval, mode: :dec)

    %{state | timer: Process.send_after(self(), :election, time)}
  end

  # Helpers

  defp key(state), do: {state.conf.name, state.conf.node}

  defp nodes, do: [Node.self() | Node.list()]
end
