defmodule Oban.Peers.Global do
  @moduledoc """
  A cluster based peer that coordinates through a distributed registry.

  Leadership is coordinated through global locks. It requires a functional distributed Erlang
  cluster, without one global plugins (Cron, Lifeline, etc.) will not function correctly.

  ## Usage

  Specify the `Global` peer in your Oban configuration.

      config :my_app, Oban,
        peer: Oban.Peers.Global,
        ...
  """

  @behaviour Oban.Peer

  use GenServer

  alias Oban.{Backoff, Notifier}
  alias __MODULE__, as: State

  defstruct [
    :conf,
    :timer,
    interval: :timer.seconds(30),
    leader?: false
  ]

  @doc false
  def child_spec(opts), do: super(opts)

  @impl Oban.Peer
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)

    GenServer.start_link(__MODULE__, struct!(State, opts), name: name)
  end

  @impl Oban.Peer
  def leader?(pid, timeout \\ 5_000) do
    GenServer.call(pid, :leader?, timeout)
  end

  @impl GenServer
  def init(state) do
    Process.flag(:trap_exit, true)

    {:ok, state, {:continue, :start}}
  end

  @impl GenServer
  def terminate(_reason, %State{timer: timer} = state) do
    if is_reference(timer), do: Process.cancel_timer(timer)

    if state.leader? do
      try do
        delete_self(state)
        notify_down(state)
      catch
        :exit, _reason -> :ok
      end
    end

    :ok
  end

  @impl GenServer
  def handle_continue(:start, %State{} = state) do
    Notifier.listen(state.conf.name, :leader)

    handle_info(:election, state)
  end

  @impl GenServer
  def handle_call(:leader?, _from, %State{} = state) do
    {:reply, state.leader?, state}
  end

  @impl GenServer
  def handle_info(:election, %State{} = state) do
    meta = %{conf: state.conf, leader: state.leader?, peer: __MODULE__}

    locked? =
      :telemetry.span([:oban, :peer, :election], meta, fn ->
        locked? = :global.set_lock(key(state), nodes(), 0)

        {locked?, %{meta | leader: locked?}}
      end)

    {:noreply, schedule_election(%{state | leader?: locked?})}
  end

  def handle_info({:notification, :leader, %{"down" => name}}, %State{conf: conf} = state) do
    if name == inspect(conf.name) do
      handle_info(:election, state)
    else
      {:noreply, state}
    end
  end

  # Helpers

  defp schedule_election(%State{interval: interval} = state) do
    time = Backoff.jitter(interval, mode: :dec)

    %{state | timer: Process.send_after(self(), :election, time)}
  end

  defp delete_self(state) do
    :global.del_lock(key(state), nodes())
  end

  defp notify_down(%{conf: conf}) do
    Notifier.notify(conf, :leader, %{down: inspect(conf.name)})
  end

  defp key(state), do: {state.conf.name, state.conf.node}

  defp nodes, do: [Node.self() | Node.list()]
end
