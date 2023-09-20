defmodule Oban.Notifier do
  @moduledoc """
  The `Notifier` coordinates listening for and publishing notifications for events in predefined
  channels.

  Every Oban supervision tree contains a notifier process, registered as `Oban.Notifier`, which
  must be an implementation of the `Oban.Notifier` behaviour. The default implementation uses
  the `LISTEN/NOTIFY` operations built into Postgres.

  All incoming notifications are relayed through the notifier to other processes.

  ## Channels

  Internally, Oban uses a variety of predefined channels with distinct responsibilities:

  * `insert` — as jobs are inserted into the database an event is published on the `insert`
    channel. Processes such as queue producers use this as a signal to dispatch new jobs.

  * `leader` — messages regarding node leadership exchanged between peers

  * `signal` — instructions to take action, such as scale a queue or kill a running job, are sent
    through the `signal` channel

  * `gossip` — arbitrary communication for coordination between nodes

  * `stager` — messages regarding job staging, e.g. notifying queues that jobs are ready for execution

  ## Examples

  Broadcasting after a job is completed:

      defmodule MyApp.Worker do
        use Oban.Worker

        @impl Oban.Worker
        def perform(job) do
          :ok = MyApp.do_work(job.args)

          Oban.Notifier.notify(Oban, :my_app_jobs, %{complete: job.id})

          :ok
        end
      end

  Listening for job complete events from another process:

      def insert_and_listen(args) do
        :ok = Oban.Notifier.listen([:my_app_jobs])

        {:ok, %{id: job_id} = job} =
          args
          |> MyApp.Worker.new()
          |> Oban.insert()

        receive do
          {:notification, :my_app_jobs, %{"complete" => ^job_id}} ->
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
  @type channel :: atom()

  @doc """
  Starts a notifier instance.
  """
  @callback start_link([option]) :: GenServer.on_start()

  @doc """
  Register the current process to receive messages from one or more channels.
  """
  @callback listen(server(), channels :: list(channel())) :: :ok

  @doc """
  Unregister current process from channels.
  """
  @callback unlisten(server(), channels :: list(channel())) :: :ok

  @doc """
  Broadcast a notification to all subscribers of a channel.
  """
  @callback notify(server(), channel :: channel(), payload :: [map()]) :: :ok

  @doc false
  def child_spec(opts) do
    conf = Keyword.fetch!(opts, :conf)
    opts = Keyword.put_new(opts, :name, conf.notifier)

    %{id: opts[:name], start: {conf.notifier, :start_link, [opts]}}
  end

  @doc """
  Register the current process to receive relayed messages for the provided channels.

  All messages are received as `JSON` and decoded _before_ they are relayed to registered
  processes. Each registered process receives a three element notification tuple in the following
  format:

      {:notification, channel :: channel(), decoded :: map()}

  ## Example

  Register to listen for all `:gossip` channel messages:

      Oban.Notifier.listen(:gossip)

  Listen for messages on multiple channels:

      Oban.Notifier.listen([:gossip, :insert, :leader, :signal, :stager])

  Listen for messages when using a custom Oban name:

      Oban.Notifier.listen(MyApp.MyOban, [:gossip, :signal])
  """
  @spec listen(server(), channel() | [channel()]) :: :ok
  def listen(name \\ Oban, channels)

  def listen(name, channel) when is_atom(channel) do
    listen(name, [channel])
  end

  def listen(name, channels) when is_list(channels) do
    unless Enum.all?(channels, &is_atom/1) do
      raise ArgumentError, "expected channels to be a list of atoms, got: #{inspect(channels)}"
    end

    conf = Oban.config(name)

    name
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
  def unlisten(name \\ Oban, channels) when is_list(channels) do
    conf = Oban.config(name)

    name
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
  def notify(conf_or_name \\ Oban, channel, payload)

  def notify(%Config{} = conf, channel, payload) when is_atom(channel) do
    with_span(conf, channel, payload, fn ->
      conf.name
      |> Registry.whereis(Oban.Notifier)
      |> conf.notifier.notify(channel, normalize_payload(payload))
    end)
  end

  def notify(name, channel, payload) when is_atom(channel) do
    name
    |> Oban.config()
    |> notify(channel, payload)
  end

  defp with_span(conf, channel, payload, fun) do
    tele_meta = %{conf: conf, channel: channel, payload: payload}

    :telemetry.span([:oban, :notifier, :notify], tele_meta, fn ->
      {fun.(), tele_meta}
    end)
  end

  defp normalize_payload(payload) do
    payload
    |> List.wrap()
    |> Enum.map(&encode/1)
  end

  @doc false
  @spec relay(Config.t(), [pid()], atom(), binary()) :: :ok
  def relay(_conf, [], _channel, _payload), do: :ok

  def relay(conf, listeners, channel, payload) when is_atom(channel) and is_binary(payload) do
    decoded = decode(payload)

    if in_scope?(decoded, conf) do
      for pid <- listeners, do: send(pid, {:notification, channel, decoded})
    end

    :ok
  end

  defp encode(payload) do
    payload
    |> to_encodable()
    |> Jason.encode!()
    |> :zlib.gzip()
    |> Base.encode64()
  end

  defp decode(payload) do
    case Base.decode64(payload) do
      {:ok, decoded} ->
        decoded
        |> :zlib.gunzip()
        |> Jason.decode!()

      # Messages emitted by the insert trigger aren't compressed.
      :error ->
        Jason.decode!(payload)
    end
  end

  defp to_encodable(%_{} = struct), do: struct

  defp to_encodable(map) when is_map(map) do
    for {key, val} <- map, into: %{}, do: {key, to_encodable(val)}
  end

  defp to_encodable(list) when is_list(list) do
    for element <- list, do: to_encodable(element)
  end

  defp to_encodable(tuple) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> to_encodable()
  end

  defp to_encodable(term), do: term

  defp in_scope?(%{"ident" => "any"}, _conf), do: true
  defp in_scope?(%{"ident" => ident}, conf), do: Config.match_ident?(conf, ident)
  defp in_scope?(_payload, _conf), do: true
end
