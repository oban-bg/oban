defmodule Oban.Crontab.Scheduler do
  @moduledoc false

  use GenServer

  import Oban.Breaker, only: [open_circuit: 1, trip_errors: 0, trip_circuit: 3]

  alias Oban.Crontab.Cron
  alias Oban.{Config, Query, Worker}

  # Make each job unique for 59 seconds to prevent double-enqueue if the node or scheduler
  # crashes. The minimum resolution for our cron jobs is 1 minute, so there is potentially
  # a one second window where a double enqueue can happen.
  @unique [period: 59]

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
    {:noreply, trip_circuit(error, [], state)}
  end

  def handle_info(:reset_circuit, state) do
    {:noreply, open_circuit(state)}
  end

  def handle_info(_message, state) do
    {:noreply, state}
  end

  defp send_poll_after(%State{poll_interval: interval} = state) do
    ref = Process.send_after(self(), :poll, interval)

    %{state | poll_ref: ref}
  end

  defp lock_and_enqueue(%State{circuit: :disabled} = state), do: state

  defp lock_and_enqueue(%State{conf: conf, poll_interval: timeout} = state) do
    %Config{repo: repo, verbose: verbose} = conf

    repo.transaction(
      fn -> if Query.acquire_lock?(conf, @lock_key), do: enqueue_jobs(conf) end,
      log: verbose,
      timeout: timeout
    )

    state
  rescue
    exception in trip_errors() -> trip_circuit(exception, __STACKTRACE__, state)
  end

  defp enqueue_jobs(%Config{crontab: crontab, timezone: timezone} = conf) do
    {:ok, datetime} = DateTime.now(timezone)

    for {cron, worker, opts} <- crontab, Cron.now?(cron, datetime) do
      {args, opts} = Keyword.pop(opts, :args, %{})

      opts = unique_opts(worker.__opts__(), opts)

      {:ok, _job} = Query.fetch_or_insert_job(conf, worker.new(args, opts))
    end
  end

  # Ensure that `unique` is deep merged and the default period has the lowest priority.
  defp unique_opts(worker_opts, crontab_opts) do
    [unique: @unique]
    |> Keyword.merge(worker_opts, &Worker.resolve_opts/3)
    |> Keyword.merge(crontab_opts, &Worker.resolve_opts/3)
  end
end
