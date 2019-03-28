defmodule Oban.Notifier do
  @moduledoc false

  use GenServer

  alias Oban.Config
  alias Postgrex.Notifications

  @type option :: {:name, module()} | {:conf, Config.t()}
  @type queue :: atom() | binary()

  @channels ~w(oban_insert oban_signal oban_status)

  defmodule State do
    @moduledoc false

    @enforce_keys [:notifications, :repo]
    defstruct [:notifications, :repo]
  end

  @spec start_link([option]) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)

    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec listen(GenServer.server(), binary()) :: :ok
  def listen(server \\ __MODULE__, channel) when channel in @channels do
    GenServer.call(server, {:listen, channel})
  end

  @spec pause_queue(GenServer.server(), queue()) :: :ok
  def pause_queue(server \\ __MODULE__, queue) when is_atom(queue) do
    GenServer.call(server, %{action: :pause, queue: queue})
  end

  @spec resume_queue(GenServer.server(), queue()) :: :ok
  def resume_queue(server \\ __MODULE__, queue) when is_atom(queue) do
    GenServer.call(server, %{action: :resume, queue: queue})
  end

  @spec scale_queue(GenServer.server(), queue(), pos_integer()) :: :ok
  def scale_queue(server \\ __MODULE__, queue, scale)
      when is_atom(queue) and is_integer(scale) and scale > 0 do
    GenServer.call(server, %{action: :scale, queue: queue, scale: scale})
  end

  @spec kill_job(GenServer.server(), pos_integer()) :: :ok
  def kill_job(server \\ __MODULE__, job_id) when is_integer(job_id) do
    GenServer.call(server, %{action: :pkill, job_id: job_id})
  end

  @impl GenServer
  def init(conf: %Config{repo: repo}) do
    {:ok, pid} = Notifications.start_link(repo.config())

    {:ok, %State{notifications: pid, repo: repo}}
  end

  @impl GenServer
  def handle_call({:listen, channel}, _from, %State{notifications: pid} = state) do
    {:ok, _} = Notifications.listen(pid, channel)

    {:reply, :ok, state}
  end

  def handle_call(message, _from, %State{repo: repo} = state) do
    encoded = Jason.encode!(message)

    {:ok, _result} = repo.query("SELECT pg_notify('oban_signal', $1)", [encoded])

    {:reply, :ok, state}
  end
end
