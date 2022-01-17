defmodule Oban.Peer do
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

  @spec leader?(Config.t() | GenServer.server()) :: boolean()
  def leader?(%Config{name: name}) do
    name
    |> Registry.via(__MODULE__)
    |> leader?()
  end

  def leader?(server), do: GenServer.call(server, :leader?)

  @spec child_spec(Keyword.t()) :: Supervisor.child_spec()
  def child_spec(opts) do
    name = Keyword.get(opts, :name, __MODULE__)

    opts
    |> super()
    |> Supervisor.child_spec(id: name)
  end

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
