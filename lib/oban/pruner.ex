defmodule Oban.Pruner do
  @moduledoc false

  use GenServer

  import Oban.Breaker, only: [open_circuit: 1, trip_errors: 0, trip_circuit: 3]

  alias Oban.{Config, Query}

  @type option :: {:name, module()} | {:conf, Config.t()}

  @lock_key 1_159_969_450_252_858_340

  defmodule State do
    @moduledoc false

    defstruct [:conf, :name, circuit: :enabled]
  end

  @spec start_link([option]) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)

    GenServer.start_link(__MODULE__, Map.new(opts), name: name)
  end

  @impl GenServer
  def init(%{conf: %Config{prune: :disabled}}) do
    :ignore
  end

  def init(%{conf: %Config{} = conf} = opts) do
    send_after(conf.prune_interval)

    {:ok, struct!(State, opts)}
  end

  @impl GenServer
  def handle_info(:prune, %State{conf: conf} = state) do
    prune(state)

    send_after(conf.prune_interval)

    {:noreply, state}
  end

  def handle_info(:reset_circuit, state) do
    {:noreply, open_circuit(state)}
  end

  def handle_info(_message, state) do
    {:noreply, state}
  end

  defp prune(%State{circuit: :disabled} = state), do: state

  defp prune(%State{conf: conf} = state) do
    %Config{repo: repo, verbose: verbose} = conf

    repo.transaction(
      fn ->
        if Query.acquire_lock?(conf, @lock_key) do
          prune_beats(conf)
          prune_jobs(conf)
        end
      end,
      log: verbose
    )
  rescue
    exception in trip_errors() -> trip_circuit(exception, __STACKTRACE__, state)
  end

  defp prune_beats(conf) do
    Query.delete_outdated_beats(conf, conf.beats_maxage, conf.prune_limit)
  end

  defp prune_jobs(conf) do
    %Config{prune: prune, prune_limit: prune_limit} = conf

    case prune do
      {:maxlen, length} ->
        Query.delete_truncated_jobs(conf, length, prune_limit)

      {:maxage, seconds} ->
        Query.delete_outdated_jobs(conf, seconds, prune_limit)
    end
  end

  defp send_after(interval) do
    Process.send_after(self(), :prune, interval)
  end
end
