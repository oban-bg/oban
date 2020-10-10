defmodule Oban.Plugins.Pruner do
  @moduledoc false

  use GenServer

  alias Oban.{Job, Query, Repo, Telemetry}

  import Ecto.Query

  defmodule State do
    @moduledoc false

    defstruct [
      :conf,
      :name,
      :timer,
      max_age: 60,
      interval: :timer.seconds(30),
      limit: 10_000,
      lock_key: 1_159_969_450_252_858_340
    ]
  end

  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)

    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl GenServer
  def init(opts) do
    Process.flag(:trap_exit, true)

    state =
      State
      |> struct!(opts)
      |> schedule_prune()

    {:ok, state}
  end

  @impl GenServer
  def terminate(_reason, state) do
    if is_reference(state.timer), do: Process.cancel_timer(state.timer)

    :ok
  end

  @impl GenServer
  def handle_info(:prune, %State{conf: conf} = state) do
    Telemetry.span(:prune, fn ->
      Repo.transaction(conf, fn -> acquire_and_prune(state) end)
    end)

    {:noreply, schedule_prune(state)}
  end

  # Scheduling

  defp schedule_prune(state) do
    %{state | timer: Process.send_after(self(), :prune, state.interval)}
  end

  # Query

  defp acquire_and_prune(state) do
    if Query.acquire_lock?(state.conf, state.lock_key) do
      delete_jobs(state.conf, state.max_age, state.limit)
    end
  end

  defp delete_jobs(conf, seconds, limit) do
    outdated_at = DateTime.add(DateTime.utc_now(), -seconds)

    subquery =
      Job
      |> where([j], j.state in ["completed", "discarded"])
      |> where([j], j.attempted_at < ^outdated_at)
      |> select([:id])
      |> limit(^limit)

    Repo.delete_all(
      conf,
      join(Job, :inner, [j], x in subquery(subquery), on: j.id == x.id)
    )
  end
end
