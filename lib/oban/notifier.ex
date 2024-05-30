defmodule Oban.Notifier do
  @moduledoc """
  The `Notifier` coordinates listening for and publishing notifications for events in predefined
  channels.

  Oban functions such as `pause_queue`, `scale_queue`, and `cancel_job` all **require a connected
  notifier to operate**. Use `status/1` to check the notifier's connectivity status and diagnose
  issues.

  ## Notifiers

  Every Oban supervision tree contains a notifier process, registered as `Oban.Notifier`, which is
  an implementation of the `Oban.Notifier` behaviour. 

  * `Oban.Notifiers.Postgres` — A Postgres notifier that uses `LISTEN/NOTIFY` to broadcast
    messages. This is the default.

  * `Oban.Notifiers.PG` — A process groups notifier that relies on Distributed Erlang to broadcast
    messages.

  * [`Oban.Notifiers.Phoenix`](https://github.com/sorentwo/oban_notifiers_phoenix) — A notifier
    that uses `Phoenix.PubSub` to broadcast messages. In addition to centralizing PubSub
    communications, it opens up the possible transports to all PubSub adapters.

  ## Channels

  All incoming notifications are relayed through the notifier to any processes listening on a
  given channel. Internally, Oban uses a variety of predefined channels with distinct
  responsibilities:

  * `insert` — as jobs are inserted an event is published on the `insert` channel. Processes such
    as queue producers use this as a signal to dispatch new jobs.

  * `leader` — messages regarding node leadership exchanged between peers

  * `signal` — instructions to take action, such as scale a queue or kill a running job, are sent
    through the `signal` channel

  * `sonar` — periodic notification checks to monitor pubsub health and determine connectivity

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

  alias Oban.{Config, Registry, Sonar}

  require Logger

  @type channel :: atom()
  @type name_or_conf :: Oban.name() | Config.t()
  @type payload :: map() | [map()]
  @type pubsub_status :: :unknown | :isolated | :solitary | :clustered

  @doc """
  Starts a notifier instance.
  """
  @callback start_link(opts :: [conf: Config.t(), name: GenServer.name()]) :: GenServer.on_start()

  @doc """
  Register the current process to receive messages from one or more channels.
  """
  @callback listen(name_or_conf(), channels :: channel() | [channel()]) :: :ok

  @doc """
  Unregister current process from channels.
  """
  @callback unlisten(name_or_conf(), channels :: channel() | [channel()]) :: :ok

  @doc """
  Broadcast a notification to all subscribers of a channel.
  """
  @callback notify(name_or_conf(), channel(), payload()) :: :ok | {:error, Exception.t()}

  @doc false
  @spec child_spec(Keyword.t()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{notifier: {notifier, note_opts}} = Keyword.fetch!(opts, :conf)

    opts =
      opts
      |> Keyword.merge(note_opts)
      |> Keyword.put_new(:name, notifier)

    %{id: opts[:name], start: {notifier, :start_link, [opts]}}
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

      Oban.Notifier.listen([:gossip, :insert, :leader, :signal])

  Listen for messages when using a custom Oban name:

      Oban.Notifier.listen(MyApp.MyOban, [:gossip, :signal])
  """
  @spec listen(name_or_conf(), channel() | [channel()]) :: :ok
  def listen(name_or_conf \\ Oban, channels) when is_atom(channels) or is_list(channels) do
    apply_callback(name_or_conf, :listen, [normalize_channels(channels)])
  end

  @doc """
  Unregister the current process from receiving relayed messages on provided channels.

  ## Example

  Stop listening for messages on the `:gossip` channel:

      Oban.Notifier.unlisten(:gossip)

  Stop listening for messages on multiple channels:

      Oban.Notifier.unlisten([:insert, :gossip])

  Stop listening for messages when using a custom Oban name:

      Oban.Notifier.unlisten(MyApp.MyOban, [:gossip])
  """
  @spec unlisten(name_or_conf(), channel() | [channel()]) :: :ok
  def unlisten(name_or_conf \\ Oban, channels) when is_atom(channels) or is_list(channels) do
    apply_callback(name_or_conf, :unlisten, [normalize_channels(channels)])
  end

  @doc """
  Broadcast a notification to listeners on all nodes.

  Notifications are scoped to the configured `prefix`. For example, if there are instances running
  with the `public` and `private` prefixes, a notification published in the `public` prefix won't
  be picked up by processes listening with the `private` prefix.

  ## Example

  Broadcast a gossip message:

      Oban.Notifier.notify(:my_channel, %{message: "hi!"})

  Broadcast multiple messages at once:

      Oban.Notifier.notify(:my_channel, [%{message: "hi!"}, %{message: "there"}])

  Broadcast using a custom instance name:

      Oban.Notifier.notify(MyOban, :my_channel, %{message: "hi!"})
  """
  @spec notify(name_or_conf(), channel(), payload()) :: :ok | {:error, Exception.t()}
  def notify(name_or_conf \\ Oban, channel, payload) when is_atom(channel) do
    conf = if is_struct(name_or_conf, Config), do: name_or_conf, else: Oban.config(name_or_conf)
    meta = %{conf: conf, channel: channel, payload: payload}

    :telemetry.span([:oban, :notifier, :notify], meta, fn ->
      payload =
        payload
        |> List.wrap()
        |> Enum.map(&encode/1)

      {apply_callback(conf, :notify, [channel, payload]), meta}
    end)
  end

  @doc """
  Check a notifier's connectivity level to see whether it's able to publish or receive messages
  from other nodes.

  Oban functions such as `pause_queue`, `scale_queue`, and `cancel_job` all require a connected
  notifier to operate. Each Oban instance runs a persistent process to monitor connectivity,
  which is exposed by this function.

  ## Statuses

  * `:unknown` — This is the default state on start before the notifier has time to determine the
    appropriate status.

  * `:isolated` — The notifier isn't receiving any messages.

    The notifier may be connected to a database but `:isolated` and unable to receive other
    message and unable to receive outside messages. Typically, this is the case for the default
    `Postgres` notifier while testing or behind a connection pooler.

  * `:solitary` — The notifier is only receiving messages from itself. This may be the case for
    the `PG` notifier when Distributed Erlang nodes aren't connected, in development, or in
    production deployments that only run a single node. If you're running multiple nodes in production
    and the status is `:solitary`, there's a connectivity issue.

  * `:clustered` — The notifier is connected and able to receive messages from other nodes. The
    `Postgres` notifier is considered clustered if it can receive notifications, while the PG
    notifier requires a functional Distributed Erlang cluster.

  ## Examples

  Check the notifier's pubsub status:

      Oban.Notifier.status()

  Check the status for a custom instance:

      Oban.Notifier.status(MyOban)
  """
  @spec status(name_or_conf()) :: pubsub_status()
  def status(name_or_conf \\ Oban) do
    name = with %Config{name: name} <- name_or_conf, do: name

    name
    |> Oban.Registry.via(Sonar)
    |> GenServer.call(:get_status)
  catch
    :exit, {:timeout, _} = reason ->
      Logger.warning("Oban.Notifier.status/1 check failed due to #{inspect(reason)}.")

      :unknown
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

  # Helpers

  defp apply_callback(name_or_conf, callback, args) do
    conf = if is_struct(name_or_conf, Config), do: name_or_conf, else: Oban.config(name_or_conf)

    %{name: name, notifier: {notifier, _}} = conf

    case Registry.whereis(name, __MODULE__) do
      pid when is_pid(pid) ->
        apply(notifier, callback, [pid | args])

      _ ->
        {:error, RuntimeError.exception("no notifier running for instance #{inspect(name)}")}
    end
  end

  defp normalize_channels(channels) do
    channels = List.wrap(channels)

    unless Enum.all?(channels, &is_atom/1) do
      raise ArgumentError, "expected channels to be a list of atoms, got: #{inspect(channels)}"
    end

    channels
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
