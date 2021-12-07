defmodule Oban.Senator do
  @moduledoc false

  use GenServer

  alias Oban.{Breaker, Repo}

  # TODO: This needs a circuit breaker
  # TODO: This needs to handle some error case, right?
  #   namely, the connection that holds the lock errors, but the senator is still alive

  @type option :: {:name, module()} | {:conf, Config.t()}

  defmodule State do
    @moduledoc false

    defstruct [
      :conf,
      :name,
      :timer,
      leader?: false,
      leader_boost: 4,
      interval: :timer.minutes(1),
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
    # Process.flag(:trap_exit, true)

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

  defp acquire_lock?(%State{conf: conf, key_base: key_base} = state) do
    key = key_base + :erlang.phash2(conf.name)

    {:ok, %{rows: [[acquired]]}} = Repo.query(conf, "SELECT pg_try_advisory_lock($1)", [key])

    acquired
  end
end
