defmodule Oban.PostgresNotifier do
  @doc """
  Postgres Listen/Notify based Notifier

  ## Caveats

  The notifications system is built on PostgreSQL's `LISTEN/NOTIFY` functionality. Notifications
  are only delivered **after a transaction completes** and are de-duplicated before publishing.
  Typically, applications run Ecto in sandbox mode while testing, but sandbox mode wraps each test
  in a separate transaction that's rolled back after the test completes. That means the
  transaction is never committed, which prevents delivering any notifications.

  To test using notifications you must run Ecto without sandbox mode enabled.
  """

  @behaviour Oban.Notifier

  use GenServer

  alias Oban.{Config, Connection, Registry, Repo}

  @mappings %{
    gossip: "oban_gossip",
    insert: "oban_insert",
    signal: "oban_signal"
  }

  defmodule State do
    @moduledoc false

    @enforce_keys [:conf]
    defstruct [:conf]
  end

  @impl Oban.Notifier
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)

    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl Oban.Notifier
  def listen(server, channels) do
    with %State{conf: conf} <- GenServer.call(server, :get_state) do
      conf.name
      |> Registry.via(Connection)
      |> GenServer.call({:listen, to_full_channels(conf, channels)})
    end
  end

  @impl Oban.Notifier
  def unlisten(server, channels) do
    with %State{conf: conf} <- GenServer.call(server, :get_state) do
      conf.name
      |> Registry.via(Connection)
      |> GenServer.call({:unlisten, to_full_channels(conf, channels)})
    end
  end

  @impl Oban.Notifier
  def notify(server, channel, payload) do
    with %State{conf: conf} <- GenServer.call(server, :get_state) do
      full_channel = Map.fetch!(@mappings, channel)

      Repo.query(
        conf,
        "SELECT pg_notify($1, payload) FROM json_array_elements_text($2::json) AS payload",
        ["#{conf.prefix}.#{full_channel}", payload]
      )

      :ok
    end
  end

  @impl GenServer
  def init(opts) do
    {:ok, struct!(State, opts)}
  end

  @impl GenServer
  def handle_call(:get_state, _from, %State{} = state) do
    {:reply, state, state}
  end

  # Helpers

  defp to_full_channels(%Config{prefix: prefix}, channels) do
    @mappings
    |> Map.take(channels)
    |> Map.values()
    |> Enum.map(&Enum.join([prefix, &1], "."))
  end
end
