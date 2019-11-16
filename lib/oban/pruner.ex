defmodule Oban.Pruner do
  @moduledoc false

  use GenServer

  import Oban.Breaker, only: [open_circuit: 1, trip_errors: 0, trip_circuit: 2]

  alias Oban.{Config, Query}

  @type option :: {:name, module()} | {:conf, Config.t()}

  defmodule State do
    @moduledoc false

    defstruct [
      :conf,
      circuit: :enabled,
      circuit_backoff: :timer.seconds(30)
    ]
  end

  @spec start_link([option]) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)

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
    state
    |> prune_beats()
    |> prune_jobs()

    send_after(conf.prune_interval)

    {:noreply, state}
  end

  def handle_info(:reset_circuit, state) do
    {:noreply, open_circuit(state)}
  end

  def handle_info(_message, state) do
    {:noreply, state}
  end

  # Pruning beats needs to respect prune being `:disabled`, but it ignores the length and age
  # configuration. Each queue generates one beat a second, 3,600 beat records per hour even when
  # the queue is idle.
  @beats_maxage_seconds 60 * 60

  defp prune_beats(%State{circuit: :disabled} = state), do: state

  defp prune_beats(%State{conf: conf} = state) do
    Query.delete_outdated_beats(conf, @beats_maxage_seconds, conf.prune_limit)

    state
  rescue
    exception in trip_errors() -> trip_circuit(exception, state)
  end

  defp prune_jobs(%State{circuit: :disabled} = state), do: state

  defp prune_jobs(%State{conf: conf} = state) do
    %Config{prune: prune, prune_limit: prune_limit} = conf

    case prune do
      {:maxlen, length} ->
        Query.delete_truncated_jobs(conf, length, prune_limit)

      {:maxage, seconds} ->
        Query.delete_outdated_jobs(conf, seconds, prune_limit)
    end

    state
  rescue
    exception in trip_errors() -> trip_circuit(exception, state)
  end

  defp send_after(interval) do
    Process.send_after(self(), :prune, interval)
  end
end
