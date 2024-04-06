defmodule Oban.Peers.Postgres do
  @moduledoc """
  A Postgres based peer that coordinates centrally through a database table.

  Postgres peers don't require clustering through distributed Erlang or any other
  interconnectivity between nodes. Leadership is coordinated through the `oban_peers` table in
  your database. With a standard Oban config the `oban_peers` table will only have one row, and
  that node is the leader.

  Applications that run multiple Oban instances will have one row per instance. For example, an
  umbrella application that runs `Oban.A` and `Oban.B` will have two rows in `oban_peers`.

  ## Usage

  Specify the `Postgres` peer in your Oban configuration.

      config :my_app, Oban,
        peer: Oban.Peers.Postgres,
        ...
  """

  @behaviour Oban.Peer

  use GenServer

  import Ecto.Query, only: [where: 2, where: 3]

  alias Oban.{Backoff, Notifier, Repo}
  alias __MODULE__, as: State

  require Logger

  defstruct [
    :conf,
    :timer,
    interval: :timer.seconds(30),
    leader?: false,
    leader_boost: 2
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
        Repo.transaction(state.conf, fn ->
          delete_self(state)
          notify_down(state)
        end)
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
  def handle_info(:election, %State{} = state) do
    meta = %{conf: state.conf, leader: state.leader?, peer: __MODULE__}

    state =
      :telemetry.span([:oban, :peer, :election], meta, fn ->
        fun = fn ->
          state
          |> delete_expired_peers()
          |> upsert_peer()
        end

        case Repo.transaction(state.conf, fun) do
          {:ok, state} ->
            {state, %{meta | leader: state.leader?}}

          {:error, :rollback} ->
            # The peer maintains its current `leader?` status on rollback—this may cause
            # inconsistency if the leader encounters an error and multiple rollbacks happen in
            # sequence. That tradeoff is acceptable because the situation is unlikely and less of
            # an issue than crashing the peer.
            {state, meta}
        end
      end)

    {:noreply, schedule_election(state)}
  rescue
    error in [DBConnection.ConnectionError, Postgrex.Error] ->
      if match?(%{postgres: %{code: :undefined_table}}, error) do
        Logger.error("""
        The `oban_peers` table is undefined and leadership is disabled.

        Run migrations up to v11 to restore peer leadership. In the meantime, distributed plugins
        (e.g. Cron, Pruner) will not run on any nodes.
        """)
      end

      {:noreply, schedule_election(%{state | leader?: false})}
  end

  def handle_info({:notification, :leader, %{"down" => name}}, %State{conf: conf} = state) do
    if name == inspect(conf.name) do
      handle_info(:election, state)
    else
      {:noreply, state}
    end
  end

  def handle_info(message, state) do
    Logger.warning("Received unexpected message: #{inspect(message)}")

    {:noreply, state}
  end

  @impl GenServer
  def handle_call(:leader?, _from, %State{} = state) do
    {:reply, state.leader?, state}
  end

  # Helpers

  defp schedule_election(%State{interval: interval} = state) do
    base = if state.leader?, do: div(interval, state.leader_boost), else: interval
    time = Backoff.jitter(base, mode: :dec)

    %{state | timer: Process.send_after(self(), :election, time)}
  end

  defp delete_expired_peers(%State{conf: conf} = state) do
    query =
      "oban_peers"
      |> where([p], p.name == ^inspect(conf.name))
      |> where([p], p.expires_at < ^DateTime.utc_now())

    Repo.delete_all(conf, query)

    state
  end

  defp delete_self(%State{conf: conf}) do
    query = where("oban_peers", name: ^inspect(conf.name), node: ^conf.node)

    Repo.delete_all(conf, query)
  end

  defp notify_down(%State{conf: conf}) do
    Notifier.notify(conf, :leader, %{down: inspect(conf.name)})
  end

  defp upsert_peer(%State{conf: conf} = state) do
    started_at = DateTime.utc_now()
    expires_at = DateTime.add(started_at, state.interval, :millisecond)

    peer_data = %{
      name: inspect(conf.name),
      node: conf.node,
      started_at: started_at,
      expires_at: expires_at
    }

    repo_opts =
      if state.leader? do
        [conflict_target: :name, on_conflict: [set: [expires_at: expires_at]]]
      else
        [on_conflict: :nothing]
      end

    case Repo.insert_all(conf, "oban_peers", [peer_data], repo_opts) do
      {1, _} -> %{state | leader?: true}
      {0, _} -> %{state | leader?: false}
    end
  end
end
