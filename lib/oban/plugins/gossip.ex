defmodule Oban.Plugins.Gossip do
  @moduledoc """
  The Gossip plugin uses PubSub to periodically exchange queue state information between all
  interested nodes. This allows Oban instances to broadcast state information regardless of which
  engine they are using, and without storing anything in the database.

  Gossip enables real-time updates across an entire cluster, and is essential to the operation of
  UIs like Oban Web.

  The Gossip plugin entirely replaced heartbeats and the legacy `oban_beats` table.

  ## Using the Plugin

  The following example demonstrates using the plugin without any configuration, which will broadcast
  the state of each local queue every 1 second:

      config :my_app, Oban,
        plugins: [Oban.Plugins.Gossip],
        ...

  Override the default options to broadcast every 5 seconds:

      config :my_app, Oban,
        plugins: [{Oban.Plugins.Gossip, interval: :timer.seconds(5)}],
        ...

  ## Options

  * `:interval` — the number of milliseconds between gossip broadcasts

  ## Instrumenting with Telemetry

  The `Oban.Plugins.Gossip` plugin adds the following metadata to the `[:oban, :plugin, :stop]` event:

  * `:gossip_count` - the number of queues that had activity broadcasted
  """

  @behaviour Oban.Plugin

  use GenServer

  alias Oban.{Notifier, Plugin, Validation}

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
      |> schedule_gossip()

    :telemetry.execute([:oban, :plugin, :init], %{}, %{conf: state.conf, plugin: __MODULE__})

    {:ok, state}
  end

  @impl GenServer
  def terminate(_reason, state) do
    if is_reference(state.timer), do: Process.cancel_timer(state.timer)

    :ok
  end

  @impl GenServer
  def handle_info(:gossip, %State{} = state) do
    meta = %{conf: state.conf, plugin: __MODULE__}

    match = [{{{state.conf.name, {:producer, :_}}, :"$1", :_}, [], [:"$1"]}]

    :telemetry.span([:oban, :plugin], meta, fn ->
      checks =
        Oban.Registry
        |> Registry.select(match)
        |> Enum.map(&safe_check(&1, state))
        |> Enum.reject(&is_nil/1)
        |> Enum.map(&sanitize_name/1)

      if Enum.any?(checks), do: Notifier.notify(state.conf, :gossip, checks)

      {:ok, Map.put(meta, :gossip_count, length(checks))}
    end)

    {:noreply, schedule_gossip(state)}
  end

  def handle_info(_message, state) do
    {:noreply, state}
  end

  # Scheduling

  defp schedule_gossip(state) do
    %{state | timer: Process.send_after(self(), :gossip, state.interval)}
  end

  # Checking

  defp safe_check(pid, state) do
    if Process.alive?(pid), do: GenServer.call(pid, :check, state.interval)
  catch
    :exit, _ -> nil
  end

  defp sanitize_name(%{name: name} = check) when is_binary(name), do: check
  defp sanitize_name(%{name: name} = check), do: %{check | name: inspect(name)}
end
