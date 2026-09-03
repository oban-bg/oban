defmodule Oban.Notifiers.PG do
  @moduledoc """
  A [PG (Process Groups)][pg] based notifier implementation that runs with Distributed Erlang.
  This notifier scales much better than `Oban.Notifiers.Postgres` but lacks its transactional
  guarantees.

  > #### Distributed Erlang {: .info}
  >
  > PG requires a functional [Distributed Erlang][de] cluster to broadcast between nodes. If your
  > application isn't clustered, then you should consider an alternative notifier such as
  > `Oban.Notifiers.Postgres`

  ## Usage

  Specify the `PG` notifier in your Oban configuration:

  ```elixir
  config :my_app, Oban,
    notifier: Oban.Notifiers.PG,
    ...
  ```

  By default, all Oban instances using the same `prefix` option will receive notifications from
  each other. You can use the `namespace` option to separate instances that are in the same
  cluster _without_ changing the prefix:

  ```elixir
  config :my_app, Oban,
    notifier: {Oban.Notifiers.PG, namespace: :custom_namespace}
    ...
  ```

  The namespace may be any term.

  [pg]: https://www.erlang.org/doc/man/pg.html
  [de]: https://elixir-lang.org/getting-started/mix-otp/distributed-tasks.html#our-first-distributed-code
  """

  @behaviour Oban.Notifier

  use GenServer

  alias Oban.Notifier

  defstruct [:conf, :namespace]

  @impl Notifier
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)

    conf = Keyword.fetch!(opts, :conf)
    opts = Keyword.put_new(opts, :namespace, conf.prefix)

    GenServer.start_link(__MODULE__, struct!(__MODULE__, opts), name: name)
  end

  @impl Notifier
  def listen(_server, _channels), do: :ok

  @impl Notifier
  def unlisten(_server, _channels), do: :ok

  @impl Notifier
  def notify(server, channel, payload) do
    with %{namespace: namespace} <- get_state(server) do
      pids = :pg.get_members(__MODULE__, namespace)

      for pid <- pids, message <- payload_to_messages(channel, payload) do
        send(pid, message)
      end

      :ok
    end
  end

  @impl GenServer
  def init(state) do
    put_state(state)

    :pg.start_link(__MODULE__)
    :pg.join(__MODULE__, state.namespace, self())

    {:ok, state}
  end

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

  @impl GenServer
  def handle_info({:notification, channel, payload}, state) do
    Notifier.relay(state.conf, channel, payload)

    {:noreply, state}
  end

  def handle_info(_message, state) do
    {:noreply, state}
  end

  ## Message Helpers

  defp payload_to_messages(channel, payload) do
    Enum.map(payload, &{:notification, channel, &1})
  end
end
