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

    GenServer.start_link(__MODULE__, Map.new(opts), name: name)
  end

  @impl GenServer
  def init(%{conf: conf}) do
    send_after(conf.prune_interval)

    {:ok, %State{conf: conf}}
  end

  @impl GenServer
  def handle_info(:prune, %State{conf: conf} = state) do
    case conf.prune do
      :disabled ->
        :ok

      {:maxlen, length} ->
        Query.delete_truncated_jobs(conf, length, conf.prune_limit)

      {:maxage, seconds} ->
        Query.delete_outdated_jobs(conf, seconds, conf.prune_limit)
    end

    send_after(conf.prune_interval)

    {:noreply, state}
  end

  defp send_after(interval) do
    Process.send_after(self(), :prune, interval)
  end
end
