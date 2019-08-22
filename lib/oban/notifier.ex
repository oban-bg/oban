defmodule Oban.Notifier do
  @moduledoc false

  use GenServer

  alias Oban.{Config, Query}
  alias Postgrex.Notifications

  @type option :: {:name, module()} | {:conf, Config.t()}
  @type channel :: :insert | :signal | :update
  @type queue :: atom()

  @mappings %{
    insert: "oban_insert",
    signal: "oban_signal",
    update: "oban_update"
  }

  @channels Map.keys(@mappings)

  defmodule State do
    @moduledoc false

    @enforce_keys [:conf]
    defstruct [:conf]
  end

  defmacro insert, do: @mappings[:insert]
  defmacro signal, do: @mappings[:signal]
  defmacro update, do: @mappings[:update]

  @spec start_link([option]) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)

    GenServer.start_link(__MODULE__, Map.new(opts), name: name)
  end

  @spec listen(module(), binary(), channel()) :: :ok
  def listen(server, prefix, channel) when is_binary(prefix) and channel in @channels do
    server
    |> conn_name()
    |> Notifications.listen("#{prefix}.#{@mappings[channel]}")

    :ok
  end

  @spec notify(module(), channel(), term()) :: :ok
  def notify(server, channel, payload) when channel in @channels do
    GenServer.call(server, {:notify, @mappings[channel], payload})
  end

  @spec pause_queue(module(), queue()) :: :ok
  def pause_queue(server, queue) when is_atom(queue) do
    notify(server, :signal, %{action: :pause, queue: queue})
  end

  @spec resume_queue(module(), queue()) :: :ok
  def resume_queue(server, queue) when is_atom(queue) do
    notify(server, :signal, %{action: :resume, queue: queue})
  end

  @spec scale_queue(module(), queue(), pos_integer()) :: :ok
  def scale_queue(server, queue, scale)
      when is_atom(queue) and is_integer(scale) and scale > 0 do
    notify(server, :signal, %{action: :scale, queue: queue, scale: scale})
  end

  @spec kill_job(module(), pos_integer()) :: :ok
  def kill_job(server, job_id) when is_integer(job_id) do
    notify(server, :signal, %{action: :pkill, job_id: job_id})
  end

  @impl GenServer
  def init(%{conf: conf, name: name}) do
    {:ok, %State{conf: conf}, {:continue, {:start, name}}}
  end

  @impl GenServer
  def handle_continue({:start, name}, %State{conf: conf} = state) do
    conn_conf = Keyword.put(conf.repo.config(), :name, conn_name(name))

    {:ok, _} = Notifications.start_link(conn_conf)

    {:noreply, state}
  end

  @impl GenServer
  def handle_call({:notify, channel, payload}, _from, %State{conf: conf} = state) do
    # Unlike `listen` the schema namespacing takes place in the Query module.
    :ok = Query.notify(conf, channel, Jason.encode!(payload))

    {:reply, :ok, state}
  end

  defp conn_name(name), do: Module.concat(name, "Conn")
end
