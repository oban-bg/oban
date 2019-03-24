defmodule Oban.Notifier do
  @moduledoc false

  use GenServer

  alias Oban.Config

  @type option :: {:name, module()} | {:conf, Config.t()}
  @type queue :: atom() | binary()

  defmodule State do
    @moduledoc false

    @enforce_keys [:repo]
    defstruct [:repo]
  end

  @spec start_link([option]) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)

    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec pause_queue(GenServer.server(), queue()) :: :ok
  def pause_queue(server, queue) do
    GenServer.call(server, %{action: :pause, queue: queue})
  end

  @spec resume_queue(GenServer.server(), queue()) :: :ok
  def resume_queue(server, queue) do
    GenServer.call(server, %{action: :resume, queue: queue})
  end

  @spec scale_queue(GenServer.server(), queue(), pos_integer()) :: :ok
  def scale_queue(server, queue, scale) do
    GenServer.call(server, %{action: :scale, queue: queue, scale: scale})
  end

  @spec kill_job(GenServer.server(), pos_integer()) :: :ok
  def kill_job(server, job_id) do
    GenServer.call(server, %{action: :pkill, job_id: job_id})
  end

  @impl GenServer
  def init(conf: %Config{repo: repo}) do
    {:ok, %State{repo: repo}}
  end

  @impl GenServer
  def handle_call(message, _from, %State{repo: repo} = state) do
    encoded = Jason.encode!(message)

    {:ok, _result} = repo.query("SELECT pg_notify('oban_signal', $1)", [encoded])

    {:reply, :ok, state}
  end
end
