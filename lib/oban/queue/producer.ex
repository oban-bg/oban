defmodule Oban.Queue.Producer do
  @moduledoc false

  use GenStage

  defmodule State do
    @moduledoc false

    @enforce_keys [:conf, :queue]
    defstruct [:conf, :queue, demand: 0]
  end

  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)

    GenStage.start_link(__MODULE__, opts, name: name)
  end

  @impl GenStage
  def init(conf: conf, queue: queue) do
    send(self(), :poll)

    {:ok, _ref} = :timer.send_interval(conf.poll_interval, :poll)

    {:producer, %State{conf: conf, queue: queue}}
  end

  @impl GenStage
  def handle_info(:poll, state), do: dispatch(state)

  @impl GenStage
  def handle_demand(demand, %State{demand: buffered_demand} = state) do
    dispatch(%{state | demand: demand + buffered_demand})
  end

  defp dispatch(%State{demand: 0} = state) do
    {:noreply, [], state}
  end

  defp dispatch(%State{conf: _conf, demand: demand, queue: _queue} = state) do
    jobs = [] # do some queue query here

    {:noreply, jobs, %{state | demand: demand - length(jobs)}}
  end
end
