defmodule Oban.Plugins.Repeater do
  @moduledoc """
  Repeatedly send inserted messages to all registered producers to simulate polling.

  ⚠️ This plugin is a **last resort** and only necessary if you're running Oban in an environment
  where neither Postgres nor PG notifications work. That situation should be rare, and limited to
  the following conditions:

  1. Running with a database connection pooler, i.e. pg_bouncer, in transaction mode
  2. Running without clustering, .i.e. distributed Erlang

  If **both** of those criteria apply and PubSub notifications won't work at all, then the
  Repeater will force local queues to poll for jobs.

  Note that the Repeater plugin won't enable other PubSub based functionality like pausing,
  scaling, starting, and stopping queues.

  ## Using the Plugin

  Tell all local, idle queues to poll for jobs every one second:

      config :my_app, Oban,
        plugins: [Oban.Plugins.Repeater],
        ...

  Override the default interval and poll every 30 seconds:

      config :my_app, Oban,
        plugins: [{Oban.Plugins.Repeater, interval: :timer.seconds(30)],
        ...

  ## Options

  * `:interval` — the number of milliseconds between notifications. The default is `1_000ms`.
  """

  @behaviour Oban.Plugin

  use GenServer

  alias Oban.{Plugin, Validation}

  @type option :: Plugin.option() | {:interval, pos_integer()}

  defmodule State do
    @moduledoc false

    defstruct [:conf, :name, :timer, interval: :timer.seconds(1)]
  end

  @impl Plugin
  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  @impl Plugin
  def validate(opts) do
    Validation.validate(opts, fn
      {:conf, _} -> :ok
      {:name, _} -> :ok
      {:interval, interval} -> Validation.validate_integer(:interval, interval)
      option -> {:error, "unknown option provided: #{inspect(option)}"}
    end)
  end

  @impl GenServer
  def init(opts) do
    Validation.validate!(opts, &validate/1)

    Process.flag(:trap_exit, true)

    state =
      State
      |> struct!(opts)
      |> schedule_notify()

    :telemetry.execute([:oban, :plugin, :init], %{}, %{conf: state.conf, plugin: __MODULE__})

    {:ok, state}
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

  # Scheduling

  defp schedule_notify(state) do
    timer = Process.send_after(self(), :notify, state.interval)

    %{state | timer: timer}
  end
end
