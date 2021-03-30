defmodule Oban.Plugins.Repeater do
  @moduledoc """
  Repeatedly send inserted messages to all registered producers to simulate polling.

  This plugin is only necessary if you're running Oban in an environment where Postgres
  notifications don't work, notably one of:

  * Using a database connection pooler in transaction mode, i.e. pg_bouncer.
  * Integration testing within the Ecto sandbox, i.e. developing Oban plugins

  ## Options

  * `:interval` — the number of milliseconds between notifications. The default is `1_000ms`.
  """

  use GenServer

  alias Oban.Config

  @type option :: {:conf, Config.t()} | {:name, GenServer.name()} | {:interval, pos_integer()}

  defmodule State do
    @moduledoc false

    defstruct [:conf, :name, :timer, interval: :timer.seconds(1)]
  end

  @doc false
  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  @impl GenServer
  def init(opts) do
    Process.flag(:trap_exit, true)

    state = struct!(State, opts)

    {:ok, schedule_notify(state)}
  end

  @impl GenServer
  def terminate(_reason, %State{timer: timer}) do
    if is_reference(timer), do: Process.cancel_timer(timer)

    :ok
  end

  @impl GenServer
  def handle_info(:notify, %State{} = state) do
    match = [{{{state.conf.name, {:producer, :"$1"}}, :"$2", :_}, [], [{{:"$1", :"$2"}}]}]
    meta = %{conf: state.conf, plugin: __MODULE__}

    :telemetry.span([:oban, :plugin], meta, fn ->
      for {queue, pid} <- Registry.select(Oban.Registry, match) do
        send(pid, {:notification, :insert, %{"queue" => queue}})
      end

      {:ok, meta}
    end)

    {:noreply, schedule_notify(state)}
  end

  defp schedule_notify(state) do
    timer = Process.send_after(self(), :notify, state.interval)

    %{state | timer: timer}
  end
end
