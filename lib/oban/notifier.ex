defmodule Oban.Notifier do
  @moduledoc """
  Behaviour for notifiers
  """

  alias Oban.Config

  @type server :: GenServer.server()
  @type option :: {:name, module()} | {:conf, Config.t()}
  @type channel :: :gossip | :insert | :signal

  @callback start_link([option]) :: GenServer.on_start()
  @callback listen(server(), channels :: list(channel())) :: :ok
  @callback unlisten(server(), channels :: list(channel())) :: :ok
  @callback notify(Config.t(), channel :: channel(), payload :: map() | [map()]) :: :ok

  @doc false
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {opts[:conf].notifier, :start_link, [opts]}
    }
  end

  @doc false
  @spec listen(Config.t(), server(), [channel]) :: :ok
  def listen(%Config{} = conf, server, channels) do
    conf.notifier.listen(server, channels)
  end

  @doc false
  @spec unlisten(Config.t(), server(), [channel]) :: :ok
  def unlisten(%Config{} = conf, server, channels) do
    conf.notifier.unlisten(server, channels)
  end

  @doc false
  @spec notify(Config.t(), channel :: channel(), payload :: map() | [map()]) :: :ok
  def notify(%Config{} = conf, channel, payload) do
    conf.notifier.notify(conf, channel, payload)
  end
end
