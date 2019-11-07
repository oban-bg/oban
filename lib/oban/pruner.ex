defmodule Oban.Pruner do
  @moduledoc false

  use GenServer

  alias Oban.{Config, Query}

  @type option :: {:name, module()} | {:conf, Config.t()}

  defmodule State do
    @moduledoc false

    defstruct [:conf]
  end

  @spec start_link([option]) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)

    GenServer.start_link(__MODULE__, opts[:conf], name: name)
  end

  @impl GenServer
  def init(%Config{} = conf) do
    send_after(conf.prune_interval)

    {:ok, %State{conf: conf}}
  end

  @impl GenServer
  def handle_info(:prune, %State{conf: conf} = state) do
    conf
    |> prune_beats()
    |> prune_jobs()

    send_after(conf.prune_interval)

    {:noreply, state}
  end

  # Pruning beats needs to respect prune being `:disabled`, but it ignores the length and age
  # configuration. Each queue generates one beat a second, 3,600 beat records per hour even when
  # the queue is idle.
  @beats_maxage_seconds 60 * 60

  defp prune_beats(%Config{prune: prune, prune_limit: prune_limit} = conf) do
    case prune do
      :disabled ->
        :ok

      {_method, _setting} ->
        Query.delete_outdated_beats(conf, @beats_maxage_seconds, prune_limit)
    end

    conf
  end

  defp prune_jobs(%Config{prune: prune, prune_limit: prune_limit} = conf) do
    case prune do
      :disabled ->
        :ok

      {:maxlen, length} ->
        Query.delete_truncated_jobs(conf, length, prune_limit)

      {:maxage, seconds} ->
        Query.delete_outdated_jobs(conf, seconds, prune_limit)
    end

    conf
  end

  defp send_after(interval) do
    Process.send_after(self(), :prune, interval)
  end
end
