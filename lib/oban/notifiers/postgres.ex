if Code.ensure_loaded?(Postgrex) do
  defmodule Oban.Notifiers.Postgres do
    @moduledoc """
    A Postgres LISTEN/NOTIFY based Notifier.

    > #### Connection Pooling {: .info}
    >
    > Postgres PubSub is fine for most applications, but it doesn't work with connection poolers
    > like [PgBouncer][pgb] when configured in _transaction_ or _statement_ mode, which is
    > standard. Notifications are required for some core Oban functionality, and you should
    > consider using an alternative notifier such as `Oban.Notifiers.PG`.

    ## Usage

    Specify the `Postgres` notifier in your Oban configuration:

        config :my_app, Oban,
          notifier: Oban.Notifiers.Postgres,
          ...

    ### Transactions and Testing

    The notifications system is built on PostgreSQL's `LISTEN/NOTIFY` functionality. Notifications
    are only delivered **after a transaction completes** and are de-duplicated before publishing.
    This means that notifications sent during a transaction will not be sent if the transaction is
    rolled back, providing consistency; this is the only notifer which provides that guarantee.
    However, it is not as scalable as other notifiers because each notification requires a
    separate query and notifications can't exceed 8kb.

    Typically, applications run Ecto in sandbox mode while testing, but sandbox mode wraps each test
    in a separate transaction that's rolled back after the test completes. That means the
    transaction is never committed, which prevents delivering any notifications.

    To test using notifications you must run Ecto without sandbox mode enabled, or use
    `Oban.Notifiers.PG` instead.

    [pgb]: https://www.pgbouncer.org/
    """

    @behaviour Oban.Notifier

    alias Oban.{Config, Notifier, Repo}
    alias Oban.Notifier.Registry, as: Listeners
    alias Postgrex.SimpleConnection, as: Simple

    defstruct [:conf, :from, channels: MapSet.new(), connected?: false]

    @impl Oban.Notifier
    def start_link(opts) do
      name = Keyword.fetch!(opts, :name)
      conf = Keyword.fetch!(opts, :conf)

      state = struct!(__MODULE__, conf: conf)

      conn_opts =
        conf
        |> Repo.config()
        |> Keyword.put(:name, name)
        |> Keyword.put_new(:auto_reconnect, true)
        |> Keyword.put_new(:sync_connect, false)

      Simple.start_link(__MODULE__, state, conn_opts)
    end

    @impl Oban.Notifier
    def listen(server, channels) do
      Simple.call(server, {:listen, channels})
    end

    @impl Oban.Notifier
    def unlisten(server, channels) do
      Simple.call(server, {:unlisten, channels})
    end

    ## Server Callbacks

    def init(state) do
      put_state(state)

      {:ok, state}
    end

    @impl Oban.Notifier
    def notify(full_channel, payload, state) when is_binary(full_channel) do
      Notifier.relay(state.conf, reverse_channel(full_channel), payload)
    end

    # This is a Notifier callback, but it has the same name and arity as SimpleConnection
    def notify(server, channel, payload) when is_atom(channel) do
      with %{conf: conf} <- get_state(server) do
        full_channel = to_full_channel(channel, conf)

        Repo.query(
          conf,
          "SELECT pg_notify($1, payload) FROM json_array_elements_text($2::json) AS payload",
          [full_channel, payload]
        )

        :ok
      end
    end

    # Every connection, including a reconnect after a crash, listens on all channels that have
    # registered listeners. The listener registry is the source of truth.
    def handle_connect(state) do
      channels =
        state.conf
        |> Listeners.channels()
        |> Enum.map(&to_full_channel(&1, state.conf))
        |> MapSet.new()

      state = %{state | channels: channels, connected?: true}

      if MapSet.size(channels) > 0 do
        listens = Enum.map_join(channels, "\n", &~s(LISTEN "#{&1}";))

        query(listens, state)
      else
        {:noreply, state}
      end
    end

    def handle_disconnect(%{} = state) do
      {:noreply, %{state | connected?: false}}
    end

    def handle_call({:listen, channels}, from, state) do
      new_channels =
        channels
        |> Enum.map(&to_full_channel(&1, state.conf))
        |> Enum.reject(&MapSet.member?(state.channels, &1))

      state = %{state | channels: Enum.into(new_channels, state.channels)}

      if state.connected? and Enum.any?(new_channels) do
        listens = Enum.map_join(new_channels, "\n", &~s(LISTEN "#{&1}";))

        query(listens, %{state | from: from})
      else
        Simple.reply(from, :ok)

        {:noreply, state}
      end
    end

    def handle_call({:unlisten, channels}, from, state) do
      # Only stop listening on channels that no longer have any registered listeners.
      del_channels =
        channels
        |> Enum.filter(&(Listeners.listeners(state.conf, &1) == []))
        |> Enum.map(&to_full_channel(&1, state.conf))
        |> Enum.filter(&MapSet.member?(state.channels, &1))

      state = %{state | channels: MapSet.difference(state.channels, MapSet.new(del_channels))}

      if state.connected? and Enum.any?(del_channels) do
        unlistens = Enum.map_join(del_channels, "\n", &~s(UNLISTEN "#{&1}";))

        query(unlistens, %{state | from: from})
      else
        Simple.reply(from, :ok)

        {:noreply, state}
      end
    end

    def handle_info(_message, state) do
      {:noreply, state}
    end

    def handle_result(_results, %{from: from} = state) do
      from && Simple.reply(from, :ok)

      {:noreply, %{state | from: nil}}
    end

    ## Helpers

    defp put_state(state) do
      Registry.update_value(Oban.Registry, {state.conf.name, Oban.Notifier}, fn _ -> state end)
    end

    defp get_state(server) do
      with [name] <- Registry.keys(Oban.Registry, server),
           {_pid, state} <- Oban.Registry.lookup(name) do
        state
      else
        _ -> {:error, RuntimeError.exception("no notifier running as #{inspect(server)}")}
      end
    end

    defp query(statement, state) do
      {:query, statement, state}
    end

    defp to_full_channel(channel, %Config{prefix: prefix}) do
      "#{prefix}.oban_#{channel}"
    end

    defp reverse_channel(full_channel) do
      [_prefix, "oban_" <> shortcut] = String.split(full_channel, ".", parts: 2)

      String.to_existing_atom(shortcut)
    end
  end
end
