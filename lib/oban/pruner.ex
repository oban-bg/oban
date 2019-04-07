defmodule Oban.Pruner do
  @moduledoc false

  use GenServer

  alias Oban.{Config, Query}

  @type option :: {:name, module()} | {:conf, Config.t()}

  @prune_interval :timer.minutes(1)

  defmodule State do
    @moduledoc false

    defstruct [:conf]
  end

  @spec start_link([option]) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)

    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl GenServer
  def init(conf: conf) do
    {:ok, %State{conf: conf}, {:continue, :start}}
  end

  @impl GenServer
  def handle_continue(:start, state) do
    {:ok, _ref} = :timer.send_interval(@prune_interval, :prune)

    handle_info(:prune, state)
  end

  @impl GenServer
  def handle_info(:prune, %State{conf: conf} = state) do
    case conf.prune do
      :disabled ->
        :ok

      {:maxlen, length} ->
        Query.delete_truncated_jobs(conf.repo, length)

      {:maxage, seconds} ->
        Query.delete_outdated_jobs(conf.repo, seconds)
    end

    {:noreply, state}
  end
end
