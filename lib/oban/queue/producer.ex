defmodule Oban.Queue.Producer do
  @moduledoc false

  use GenStage

  alias Oban.{Config, Query}

  @type option ::
          {:name, module()}
          | {:conf, Config.t()}
          | {:queue, binary()}

  defmodule State do
    @moduledoc false

    @enforce_keys [:conf, :queue]
    defstruct [:conf, :queue, demand: 0, paused: false]
  end

  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)

    GenStage.start_link(__MODULE__, opts, name: name)
  end

  @spec pause(GenServer.name()) :: :ok
  def pause(producer) do
    GenStage.call(producer, :pause)
  end

  @impl GenStage
  def init(conf: conf, queue: queue) do
    send(self(), :rescue_orphans)
    send(self(), :poll)

    {:ok, _ref} = :timer.send_interval(conf.poll_interval, :poll)

    {:producer, %State{conf: conf, queue: queue}}
  end

  @impl GenStage
  def handle_info(:poll, state), do: dispatch(state)

  def handle_info(:rescue_orphans, %State{conf: conf, queue: queue} = state) do
    Query.rescue_orphaned_jobs(conf.repo, queue)

    {:noreply, [], state}
  end

  @impl GenStage
  def handle_call(:pause, _from, %State{} = state) do
    {:reply, :ok, [], %{state | demand: 0, paused: true}}
  end

  @impl GenStage
  def handle_demand(demand, %State{demand: buffered_demand} = state) do
    dispatch(%{state | demand: demand + buffered_demand})
  end

  defp dispatch(%State{demand: demand, paused: paused} = state) when demand == 0 or paused do
    {:noreply, [], state}
  end

  defp dispatch(%State{conf: conf, demand: demand, queue: queue} = state) do
    {count, jobs} =
      case Query.fetch_available_jobs(conf.repo, queue, demand) do
        {0, nil} -> {0, []}
        {count, jobs} -> {count, jobs}
      end

    {:noreply, jobs, %{state | demand: demand - count}}
  end
end
