defmodule Oban.Crontab.Scheduler do
  @moduledoc false

  use GenServer

  import Oban.Breaker, only: [trip_errors: 0, trip_circuit: 2]

  alias Oban.Crontab.Cron
  alias Oban.{Config, Query}

  # Make each job unique for 59 seconds to prevent double-enqueue if the node or scheduler
  # crashes. The minimum resolution for our cron jobs is 1 minute, so there is potentially
  # a one second window where a double enqueue can happen.
  @unique [period: 59]

  @type option :: {:name, module()} | {:conf, Config.t()}

  defmodule State do
    @moduledoc false

    @enforce_keys [:conf]
    defstruct [
      :conf,
      :conn,
      :poll_ref,
      circuit: :enabled,
      circuit_backoff: :timer.seconds(30),
      lock_held?: false,
      lock_key: 325_556_101,
      poll_interval: :timer.seconds(60)
    ]
  end

  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)

    GenServer.start_link(__MODULE__, opts[:conf], name: name)
  end

  # There isn't any reason to run the server without cron jobs. We save a dedicated PG connection
  # by returning :ignore.
  @impl GenServer
  def init(%Config{crontab: []}) do
    :ignore
  end

  def init(%Config{} = conf) do
    Process.flag(:trap_exit, true)

    {:ok, struct!(State, conf: conf), {:continue, :start}}
  end

  @impl GenServer
  def handle_continue(:start, state) do
    handle_info(:poll, connect(state))
  end

  @impl GenServer
  def terminate(_reason, %State{poll_ref: poll_ref}) do
    if not is_nil(poll_ref), do: Process.cancel_timer(poll_ref)

    :ok
  end

  @impl GenServer
  def handle_info(:poll, state) do
    state =
      state
      |> send_poll_after()
      |> aquire_lock()
      |> enqueue_jobs()

    {:noreply, state}
  end

  def handle_info({:EXIT, _pid, error}, %State{} = state) do
    {:noreply, trip_circuit(error, state)}
  end

  def handle_info(:reset_circuit, %State{circuit: :disabled} = state) do
    {:noreply, connect(state)}
  end

  defp connect(%State{conf: conf} = state) do
    case Postgrex.start_link(conf.repo.config()) do
      {:ok, conn} -> %{state | conn: conn}
      {:error, error} -> trip_circuit(error, state)
    end
  end

  defp send_poll_after(%State{poll_interval: interval} = state) do
    ref = Process.send_after(self(), :poll, interval)

    %{state | poll_ref: ref}
  end

  defp aquire_lock(%State{lock_held?: true} = state), do: state

  defp aquire_lock(%State{circuit: :disabled} = state) do
    %{state | lock_held?: false}
  end

  defp aquire_lock(%State{conn: conn, lock_key: lock_key} = state) do
    %{rows: [[aquired?]]} = Postgrex.query!(conn, "SELECT pg_try_advisory_lock($1)", [lock_key])

    %{state | lock_held?: aquired?}
  rescue
    exception in trip_errors() -> trip_circuit(exception, state)
  end

  defp enqueue_jobs(%State{circuit: :disabled} = state), do: state

  defp enqueue_jobs(%State{conf: conf} = state) do
    for {cron, worker, opts} <- conf.crontab, Cron.now?(cron) do
      {args, opts} = Keyword.pop(opts, :args, %{})

      opts = Keyword.put_new(opts, :unique, @unique)

      {:ok, _job} = Query.fetch_or_insert_job(conf, worker.new(args, opts))
    end

    state
  rescue
    exception in trip_errors() -> trip_circuit(exception, state)
  end
end
