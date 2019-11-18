defmodule Oban.Crontab.Scheduler do
  @moduledoc false

  use GenServer

  import Oban.Breaker, only: [open_circuit: 1, trip_errors: 0, trip_circuit: 2]

  alias Oban.Crontab.Cron
  alias Oban.{Config, Query}

  # Make each job unique for 59 seconds to prevent double-enqueue if the node or scheduler
  # crashes. The minimum resolution for our cron jobs is 1 minute, so there is potentially
  # a one second window where a double enqueue can happen.
  @unique [period: 59]

  # Use an extremely large 64bit integer as the key value to prevent any chance of intersecting
  # with application keyspace.
  @lock_key 1_149_979_440_242_868_330

  @type option :: {:name, module()} | {:conf, Config.t()}

  defmodule State do
    @moduledoc false

    @enforce_keys [:conf]
    defstruct [
      :conf,
      :name,
      :poll_ref,
      circuit: :enabled,
      poll_interval: :timer.seconds(60)
    ]
  end

  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    name = Keyword.get(opts, :name, __MODULE__)

    GenServer.start_link(__MODULE__, opts[:conf], name: name)
  end

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
    handle_info(:poll, state)
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
      |> lock_and_enqueue()

    {:noreply, state}
  end

  def handle_info({:EXIT, _pid, error}, %State{} = state) do
    {:noreply, trip_circuit(error, state)}
  end

  def handle_info(:reset_circuit, state) do
    {:noreply, open_circuit(state)}
  end

  defp send_poll_after(%State{poll_interval: interval} = state) do
    ref = Process.send_after(self(), :poll, interval)

    %{state | poll_ref: ref}
  end

  defp lock_and_enqueue(%State{circuit: :disabled} = state), do: state

  defp lock_and_enqueue(%State{conf: conf, poll_interval: timeout} = state) do
    %Config{repo: repo, verbose: verbose} = conf

    repo.transaction(
      fn -> if acquire_lock?(conf), do: enqueue_jobs(conf) end,
      log: verbose,
      timeout: timeout
    )

    state
  rescue
    exception in trip_errors() -> trip_circuit(exception, state)
  end

  defp acquire_lock?(%Config{repo: repo, verbose: verbose}) do
    %{rows: [[locked?]]} =
      repo.query!(
        "SELECT pg_try_advisory_xact_lock($1)",
        [@lock_key],
        log: verbose
      )

    locked?
  end

  defp enqueue_jobs(conf) do
    for {cron, worker, opts} <- conf.crontab, Cron.now?(cron) do
      {args, opts} = Keyword.pop(opts, :args, %{})

      opts = Keyword.put_new(opts, :unique, @unique)

      {:ok, _job} = Query.fetch_or_insert_job(conf, worker.new(args, opts))
    end
  end
end
