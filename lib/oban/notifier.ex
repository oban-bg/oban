defmodule Oban.Notifier do
  @moduledoc """
  The `Notifier` coordinates listening for and publishing notifications for events in predefined
  channels.

  Every Oban supervision tree contains a notifier process, registered as `Oban.Notifier`, which
  can be any implementation of the `Oban.Notifier` behaviour. The default one is
  `Oban.PostgresNotifier`, which relies on Postgres `LISTEN/NOTIFY`. All incoming notifications
  are relayed through the notifier to other processes.

  ## Channels

  The notifier recognizes three predefined channels, each with a distinct responsibility:

  * `gossip` — arbitrary communication between nodes or jobs are sent on the `gossip` channel
  * `insert` — as jobs are inserted into the database an event is published on the `insert`
    channel. Processes such as queue producers use this as a signal to dispatch new jobs.
  * `signal` — instructions to take action, such as scale a queue or kill a running job, are sent
    through the `signal` channel.

  The `insert` and `signal` channels are primarily for internal use. Use the `gossip` channel to
  send notifications between jobs or processes in your application.

  ## Examples

  Broadcasting after a job is completed:

      defmodule MyApp.Worker do
        use Oban.Worker

        @impl Oban.Worker
        def perform(job) do
          :ok = MyApp.do_work(job.args)

          Oban.Notifier.notify(Oban, :gossip, %{complete: job.id})

          :ok
        end
      end

  Listening for job complete events from another process:

      def insert_and_listen(args) do
        {:ok, job} =
          args
          |> MyApp.Worker.new()
          |> Oban.insert()

        receive do
          {:notification, :gossip, %{"complete" => ^job.id}} ->
            IO.puts("Other job complete!")
        after
          30_000 ->
            IO.puts("Other job didn't finish in 30 seconds!")
        end
      end
  """

  alias Oban.{Config, Registry}

  @type server :: GenServer.server()
  @type option :: {:name, module()} | {:conf, Config.t()}
  @type channel :: :gossip | :insert | :signal

  @doc "Starts a notifier"
  @callback start_link([option]) :: GenServer.on_start()

  @doc "Register current process to receive messages from some channels"
  @callback listen(server(), channels :: list(channel())) :: :ok

  @doc "Unregister current process from channels"
  @callback unlisten(server(), channels :: list(channel())) :: :ok

  @doc "Broadcast a notification in a channel"
  @callback notify(server(), channel :: channel(), payload :: [map()]) :: :ok

  defguardp is_channel(channel) when channel in [:gossip, :insert, :signal]

  @doc false
  def child_spec(opts) do
    conf = Keyword.fetch!(opts, :conf)

    %{id: __MODULE__, start: {conf.notifier, :start_link, [opts]}}
  end

  @doc """
  Register the current process to receive relayed messages for the provided channels.

  All messages are received as `JSON` and decoded _before_ they are relayed to registered
  processes. Each registered process receives a three element notification tuple in the following
  format:

      {:notification, channel :: channel(), decoded :: map()}

  ## Example

  Register to listen for all `:gossip` channel messages:

      Oban.Notifier.listen([:gossip])

  Listen for messages on all channels:

      Oban.Notifier.listen([:gossip, :insert, :signal])

  Listen for messages when using a custom Oban name:

      Oban.Notifier.listen(MyApp.MyOban, [:gossip, :insert, :signal])
  """
  @spec listen(server(), [channel]) :: :ok
  def listen(server \\ Oban, channels) when is_list(channels) do
    :ok = validate_channels!(channels)

    conf = Oban.config(server)

    server
    |> Registry.whereis(Oban.Notifier)
    |> conf.notifier.listen(channels)
  end

  @doc """
  Unregister the current process from receiving relayed messages on provided channels.

  ## Example

  Stop listening for messages on the `:gossip` channel:

      Oban.Notifier.unlisten([:gossip])

  Stop listening for messages when using a custom Oban name:

      Oban.Notifier.unlisten(MyApp.MyOban, [:gossip])
  """
  @spec unlisten(server(), [channel]) :: :ok
  def unlisten(server \\ Oban, channels) when is_list(channels) do
    conf = Oban.config(server)

    server
    |> Registry.whereis(Oban.Notifier)
    |> conf.notifier.unlisten(channels)
  end

  @doc """
  Broadcast a notification to listeners on all nodes.

  Notifications are scoped to the configured `prefix`. For example, if there are instances running
  with the `public` and `private` prefixes, a notification published in the `public` prefix won't
  be picked up by processes listening with the `private` prefix.

  Using notify/3 with a config is soft deprecated. Use a server as the first argument instead

  ## Example

  Broadcast a gossip message:

      Oban.Notifier.notify(:gossip, %{message: "hi!"})
  """
  @spec notify(Config.t() | server(), channel :: channel(), payload :: map() | [map()]) :: :ok
  def notify(conf_or_server \\ Oban, channel, payload)

  def notify(%Config{} = conf, channel, payload) when is_channel(channel) do
    with_span(conf, channel, payload, fn ->
      conf.name
      |> Registry.whereis(Oban.Notifier)
      |> conf.notifier.notify(channel, normalize_payload(payload))
    end)
  end

  def notify(server, channel, payload) when is_channel(channel) do
    conf = Oban.config(server)

    with_span(conf, channel, payload, fn ->
      conf.name
      |> Registry.whereis(Oban.Notifier)
      |> conf.notifier.notify(channel, normalize_payload(payload))
    end)
  end

  defp with_span(conf, channel, payload, cb) do
    tele_meta = %{conf: conf, channel: channel, payload: payload}

    :telemetry.span([:oban, :notifier, :notify], tele_meta, fn ->
      {cb.(), tele_meta}
    end)
  end

  defp normalize_payload(payload) do
    payload
    |> List.wrap()
    |> Enum.map(&Jason.encode!/1)
  end

  defp validate_channels!([]), do: :ok
  defp validate_channels!([head | tail]) when is_channel(head), do: validate_channels!(tail)
  defp validate_channels!([head | _]), do: raise(ArgumentError, "unexpected channel: #{head}")
end
