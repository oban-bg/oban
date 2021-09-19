defmodule Oban.Plugins.Gossip do
  @moduledoc """
  Periodically broadcast queue activity to the gossip notification channel.

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

  use GenServer

  alias Oban.{Config, Notifier}

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

    state =
      State
      |> struct!(opts)
      |> schedule_gossip()

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

    :telemetry.span(state.conf.telemetry_prefix ++ [:plugin], meta, fn ->
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

  defp schedule_gossip(state) do
    %{state | timer: Process.send_after(self(), :gossip, state.interval)}
  end

  defp safe_check(pid, state) do
    if Process.alive?(pid), do: GenServer.call(pid, :check, state.interval)
  catch
    :exit, _ -> nil
  end

  defp sanitize_name(%{name: name} = check) when is_binary(name), do: check
  defp sanitize_name(%{name: name} = check), do: %{check | name: inspect(name)}
end
