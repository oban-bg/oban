defmodule Oban.Peer do
  @moduledoc """
  The `Peer` module maintains leadership for a particular Oban instance within a cluster.

  Leadership is used by plugins, primarily, to prevent duplicate work accross nodes. For example,
  only the leader's `Cron` plugin will insert new jobs. You can use peer leadership to extend Oban
  with custom plugins, or even within your own application.

  Note a few important details about how peer leadership operates:

  * Each Oban instances supervises a distinct `Oban.Peer` instance. That means that with multiple
    Oban instances on the same node one instance may be the leader, while the others aren't.

  * Leadership is coordinated through the `oban_peers` table in your database. It doesn't require
    distributed Erlang or any other interconnectivity.

  * Without leadership some plugins may not run on any node.

  ## Examples

  Check leadership for the default Oban instance:

      Oban.Peer.leader?()
      # => true

  That is identical to using the name `Oban`:

      Oban.Peer.leader?(Oban)
      # => true

  Check leadership for a couple of instances:

      Oban.Peer.leader?(Oban.A)
      # => true

      Oban.Peer.leader?(Oban.B)
      # => false
  """

  use GenServer

  import Ecto.Query, only: [where: 3]

  alias Oban.{Backoff, Config, Registry, Repo}

  require Logger

  @type option ::
          {:name, module()}
          | {:conf, Config.t()}
          | {:interval, timeout()}

  defmodule State do
    @moduledoc false

    defstruct [
      :conf,
      :name,
      :timer,
      interval: :timer.seconds(30),
      leader?: false,
      leader_boost: 2
    ]
  end

  @doc """
  Check whether the current instance leads the cluster.

  ## Example

  Check leadership for the default Oban instance:

      Oban.Peer.leader?()
      # => true

  Check leadership for an alternate instance named `Oban.Private`:

      Oban.Peer.leader?(Oban.Private)
      # => true
  """
  @spec leader?(Config.t() | GenServer.server()) :: boolean()
  def leader?(name \\ Oban)

  def leader?(%Config{name: name}), do: leader?(name)

  def leader?(pid) when is_pid(pid) do
    GenServer.call(pid, :leader?)
  end

  def leader?(name) do
    name
    |> Registry.whereis(__MODULE__)
    |> leader?()
  end

  @doc false
  @spec child_spec(Keyword.t()) :: Supervisor.child_spec()
  def child_spec(opts) do
    name = Keyword.get(opts, :name, __MODULE__)

    opts
    |> super()
    |> Supervisor.child_spec(id: name)
  end

  @doc false
  @spec start_link([option]) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  @impl GenServer
  def init(opts) do
    Process.flag(:trap_exit, true)

    case Keyword.fetch!(opts, :conf) do
      %{plugins: []} ->
        :ignore

      _ ->
        {:ok, struct!(State, opts), {:continue, :start}}
    end
  end

  @impl GenServer
  def terminate(_reason, %State{timer: timer}) do
    if is_reference(timer), do: Process.cancel_timer(timer)

    :ok
  end

  @impl GenServer
  def handle_continue(:start, %State{} = state) do
    handle_info(:election, state)
  end

  @impl GenServer
  def handle_info(:election, %State{} = state) do
    state =
      state
      |> delete_expired_peers()
      |> upsert_peer()

    {:noreply, schedule_election(state)}
  rescue
    error in [Postgrex.Error] ->
      if error.postgres.code == :undefined_table do
        Logger.warn("""
        The `oban_peers` table is undefined and leadership is disabled.

        Run migrations up to v11 to restore peer leadership. In the meantime, distributed plugins
        (e.g. Cron, Pruner, Stager) will not run on any nodes.
        """)
      end

      {:noreply, schedule_election(%{state | leader?: false})}
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
