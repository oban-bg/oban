defmodule Oban.Notifier do
  @moduledoc false

  use GenServer

  alias Oban.Config
  alias Postgrex.Notifications

  @type option :: {:name, module()} | {:conf, Config.t()}
  @type queue :: atom()

  @gossip "oban_gossip"
  @insert "oban_insert"
  @signal "oban_signal"

  @channels [@gossip, @insert, @signal]

  defmodule State do
    @moduledoc false

    @enforce_keys [:repo]
    defstruct [:repo]
  end

  @spec start_link([option]) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)

    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec listen(module(), binary()) :: :ok
  def listen(server \\ __MODULE__, channel) when channel in @channels do
    server
    |> conn_name()
    |> Notifications.listen(channel)

    :ok
  end

  @spec notify(module(), binary(), term()) :: :ok
  def notify(server \\ __MODULE__, channel, payload) when channel in @channels do
    GenServer.call(server, {:notify, channel, payload})
  end

  @spec pause_queue(module(), queue()) :: :ok
  def pause_queue(server \\ __MODULE__, queue) when is_atom(queue) do
    notify(server, @signal, %{action: :pause, queue: queue})
  end

  @spec resume_queue(module(), queue()) :: :ok
  def resume_queue(server \\ __MODULE__, queue) when is_atom(queue) do
    notify(server, @signal, %{action: :resume, queue: queue})
  end

  @spec scale_queue(module(), queue(), pos_integer()) :: :ok
  def scale_queue(server \\ __MODULE__, queue, scale)
      when is_atom(queue) and is_integer(scale) and scale > 0 do
    notify(server, @signal, %{action: :scale, queue: queue, scale: scale})
  end

  @spec kill_job(module(), pos_integer()) :: :ok
  def kill_job(server \\ __MODULE__, job_id) when is_integer(job_id) do
    notify(server, @signal, %{action: :pkill, job_id: job_id})
  end

  @impl GenServer
  def init(conf: %Config{repo: repo}, name: name) do
    {:ok, %State{repo: repo}, {:continue, {:start, name}}}
  end

  @impl GenServer
  def handle_continue({:start, name}, %State{repo: repo} = state) do
    conn_conf = Keyword.put(repo.config(), :name, conn_name(name))

    {:ok, _} = Notifications.start_link(conn_conf)

    {:noreply, state}
  end

  @impl GenServer
  def handle_call({:notify, channel, payload}, _from, %State{repo: repo} = state) do
    encoded = Jason.encode!(payload)

    {:ok, _result} = repo.query("SELECT pg_notify($1, $2)", [channel, encoded])

    {:reply, :ok, state}
  end

  defp conn_name(name), do: Module.concat(name, "Conn")
end
