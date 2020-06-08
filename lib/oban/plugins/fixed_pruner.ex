defmodule Oban.Plugins.FixedPruner do
  @moduledoc false

  use GenServer

  alias Oban.{Config, Job, Query, Telemetry}

  import Ecto.Query

  @lock_key 1_159_969_450_252_858_340
  @prune_age 60
  @prune_interval :timer.seconds(30)
  @prune_limit 100_000

  defmodule State do
    @moduledoc false

    defstruct [:conf, :interval, :name]
  end

  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)

    opts =
      opts
      |> Keyword.put_new(:interval, @prune_interval)
      |> Map.new()

    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl GenServer
  def init(opts) do
    Process.send_after(self(), :prune, opts.interval)

    {:ok, struct!(State, opts)}
  end

  @impl GenServer
  def handle_info(:prune, %State{conf: conf} = state) do
    %Config{repo: repo, log: log} = conf

    Telemetry.span(:prune, fn ->
      repo.transaction(fn -> acquire_and_prune(conf) end, log: log)
    end)

    Process.send_after(self(), :prune, state.interval)

    {:noreply, state}
  end

  defp acquire_and_prune(conf) do
    if Query.acquire_lock?(conf, @lock_key) do
      delete_jobs(conf, @prune_age, @prune_limit)
    end
  end

  defp delete_jobs(conf, seconds, limit) do
    %Config{prefix: prefix, repo: repo, log: log} = conf

    outdated_at = DateTime.add(DateTime.utc_now(), -seconds)

    subquery =
      Job
      |> where([j], j.state in ["completed", "discarded"])
      |> where([j], j.attempted_at < ^outdated_at)
      |> select([:id])
      |> limit(^limit)

    Job
    |> join(:inner, [j], x in subquery(subquery, prefix: prefix), on: j.id == x.id)
    |> repo.delete_all(log: log, prefix: prefix)
  end
end
