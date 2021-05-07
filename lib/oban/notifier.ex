defmodule Oban.Notifier do
  @moduledoc """
  Behaviour for notifiers
  """

  alias Oban.{Config, Registry}

  @type server :: GenServer.server()
  @type option :: {:name, module()} | {:conf, Config.t()}
  @type channel :: :gossip | :insert | :signal

  @callback start_link([option]) :: GenServer.on_start()
  @callback listen(server(), channels :: list(channel())) :: :ok
  @callback unlisten(server(), channels :: list(channel())) :: :ok
  @callback notify(server(), channel :: channel(), payload :: map() | [map()]) :: :ok

  @mappings %{
    gossip: "oban_gossip",
    insert: "oban_insert",
    signal: "oban_signal"
  }

  @channels Map.keys(@mappings)

  defguardp is_channel(channel) when channel in @channels

  @doc false
  def child_spec(opts) do
    conf = Keyword.fetch!(opts, :conf)

    %{
      id: __MODULE__,
      start: {conf.notifier, :start_link, [opts]}
    }
  end

  @doc false
  @spec listen(server(), [channel]) :: :ok
  def listen(server, channels) do
    :ok = validate_channels!(channels)

    conf = Oban.config(server)

    server
    |> Registry.whereis(Oban.Notifier)
    |> conf.notifier.listen(channels)
  end

  @doc false
  @spec unlisten(server(), [channel]) :: :ok
  def unlisten(server, channels) do
    conf = Oban.config(server)

    server
    |> Registry.whereis(Oban.Notifier)
    |> conf.notifier.unlisten(channels)
  end

  @doc """
  Sends a notification to a channel

  Using notify/3 with a config is soft deprecated. Use a server as the first
  argument instead
  """
  @spec notify(Config.t() | server(), channel :: channel(), payload :: map() | [map()]) :: :ok
  def notify(%Config{} = conf, channel, payload) when is_channel(channel) do
    conf.name
    |> Registry.whereis(Oban.Notifier)
    |> conf.notifier.notify(channel, payload)
  end

  def notify(server, channel, payload) when is_channel(channel) do
    conf = Oban.config(server)

    conf.name
    |> Registry.whereis(Oban.Notifier)
    |> conf.notifier.notify(channel, payload)
  end

  @doc false
  @spec mappings() :: %{channel => String.t()}
  def mappings, do: @mappings

  @doc false
  @spec mapping(channel()) :: String.t()
  def mapping(channel) when is_channel(channel), do: @mappings[channel]

  defp validate_channels!([]), do: :ok
  defp validate_channels!([head | tail]) when is_channel(head), do: validate_channels!(tail)
  defp validate_channels!([head | _]), do: raise(ArgumentError, "unexpected channel: #{head}")
end
