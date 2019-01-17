defmodule Oban.Queue.Producer do
  @moduledoc false

  use GenStage

  defmodule State do
    @moduledoc false

    @enforce_keys [:conf, :db, :queue]
    defstruct [:conf, :db, :queue, demand: 0, interval: 10]
  end

  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)

    GenStage.start_link(__MODULE__, opts, name: name)
  end

  @impl GenStage
  def init(opts) do
    send(self(), :pull)

    {:producer, struct!(State, opts)}
  end

  @impl GenStage
  def handle_info(:pull, state) do
    state
    |> schedule_pull()
    |> dispatch()
  end

  @impl GenStage
  def handle_demand(demand, %State{demand: buffered_demand} = state) do
    dispatch(%{state | demand: demand + buffered_demand})
  end

  defp dispatch(%State{demand: 0} = state) do
    {:noreply, [], state}
  end

  defp dispatch(%State{conf: conf, db: db, demand: demand, queue: queue} = state) do
    jobs = conf.database.pull(db, queue, demand, conf)

    {:noreply, jobs, %{state | demand: demand - length(jobs)}}
  end

  defp schedule_pull(%State{interval: interval} = state) do
    Process.send_after(self(), :pull, interval)

    state
  end
end
