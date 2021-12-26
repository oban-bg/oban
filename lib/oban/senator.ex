defmodule Oban.Senator do
  @moduledoc false

  use GenServer

  alias Oban.{Breaker, Connection, Registry}

  # TODO: This needs a circuit breaker
  # TODO: Monitor the connection and relinquish leadership on DOWN

  @type option :: {:name, module()} | {:conf, Config.t()}

  defmodule State do
    @moduledoc false

    defstruct [
      :conf,
      :timer,
      leader?: false,
      leader_boost: 2,
      interval: :timer.seconds(30),
      key_base: 428_836_387_984
    ]
  end

  @spec leader?(GenServer.server()) :: boolean()
  def leader?(pid), do: GenServer.call(pid, :leader?)

  @spec start_link([option]) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)

    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl GenServer
  def init(opts) do
    {:ok, struct!(State, opts), {:continue, :start}}
  end

  @impl GenServer
  def terminate(_reason, %State{timer: timer}) do
    if is_reference(timer), do: Process.cancel_timer(timer)

    :ok
  end

  @impl GenServer
  def handle_continue(:start, state) do
    handle_info(:election, state)
  end

  @impl GenServer
  def handle_info(:election, state) do
    state =
      state
      |> election()
      |> schedule_election()

    {:noreply, state}
  end

  @impl GenServer
  def handle_call(:leader?, _from, state) do
    {:reply, state.leader?, state}
  end

  defp election(%State{} = state) do
    leader? = state.leader? or acquire_lock?(state)

    %{state | leader?: leader?}
  end

  defp schedule_election(%State{interval: interval} = state) do
    base = if state.leader?, do: div(interval, state.leader_boost), else: interval
    time = Breaker.jitter(base)

    %{state | timer: Process.send_after(self(), :election, time)}
  end

  defp acquire_lock?(%State{conf: conf, key_base: key_base}) do
    key = key_base + :erlang.phash2(conf.name)
    query = "SELECT pg_try_advisory_lock(#{key})"

    {:ok, %{rows: [[raw_boolean]]}} =
      conf.name
      |> Registry.via(Connection)
      |> GenServer.call({:query, query})

    raw_boolean == "t"
  end
end
