defmodule Oban.Peer do
  @moduledoc """
  The `Peer` module maintains leadership for a particular Oban instance within a cluster.

  Leadership is used by plugins, primarily, to prevent duplicate work across nodes. For example,
  only the leader's `Cron` plugin will try inserting new jobs. You can use peer leadership to
  extend Oban with custom plugins, or even within your own application.

  Note a few important details about how peer leadership operates:

  * Each peer checks for leadership at a 30 second interval. When the leader exits it broadcasts a
    message to all other peers to encourage another one to assume leadership.

  * Each Oban instance supervises a distinct `Oban.Peer` instance. That means that with multiple
    Oban instances on the same node one instance may be the leader, while the others aren't.

  * Without leadership, global plugins (Cron, Lifeline, Stager, etc.), will not run on any node.

  ## Available Peer Implementations

  There are two built-in peering modules:

  * `Oban.Peers.Database` — uses table-based leadership through the `oban_peers` table and works
    in any environment, with or without clustering. Only one node (per instance name) will have a
    row in the peers table, that node is the leader. This is the default.

  * `Oban.Peers.Global` — coordinates global locks through distributed Erlang, requires
    distributed Erlang.

  You can specify the peering module to use in your Oban configuration:

      config :my_app, Oban,
        peer: Oban.Peers.Database, # default value
        ...

  If in doubt, you can call `Oban.config()` to see which module is being used.

  ## Examples

  Check leadership for the default Oban instance:

      Oban.Peer.leader?()
      # => true

  That is identical to using the name `Oban`:

      Oban.Peer.leader?(Oban)
      # => true

  Check leadership for a couple of instances:

      Oban.Peer.leader?(Oban.A)
      # => true

      Oban.Peer.leader?(Oban.B)
      # => false
  """

  alias Oban.{Config, Registry}

  require Logger

  @type option :: [name: module(), conf: Config.t(), interval: timeout()]

  @type conf_or_name :: Config.t() | GenServer.name()

  @doc """
  Starts a peer instance.
  """
  @callback start_link([option()]) :: GenServer.on_start()

  @doc """
  Check whether the current peer instance leads the cluster.
  """
  @callback leader?(GenServer.server()) :: boolean()

  @doc """
  Check which node's peer instance currently leads the cluster.
  """
  @callback get_leader(GenServer.server()) :: nil | String.t()

  @doc false
  @spec child_spec(Keyword.t()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{peer: {peer, peer_opts}} = Keyword.fetch!(opts, :conf)

    opts =
      opts
      |> Keyword.merge(peer_opts)
      |> Keyword.put_new(:name, peer)

    %{id: opts[:name], start: {peer, :start_link, [opts]}}
  end

  @doc """
  Get the name and node of the instance that currently leads the cluster.

  ## Example

  Get the leader node for the default Oban instance:

      Oban.Peer.get_leader()
      "web.1"

  Get the leader node for an alternate instance named `Oban.Private`

      Oban.Peer.get_leader(Oban.Private)
      "web.1"
  """
  @spec get_leader(conf_or_name, timeout()) :: nil | String.t()
  def get_leader(conf_or_name \\ Oban, timeout \\ 5_000) do
    safe_call(conf_or_name, :get_leader, timeout, nil)
  end

  @doc """
  Check whether the current instance leads the cluster.

  ## Example

  Check leadership for the default Oban instance:

      Oban.Peer.leader?()
      # => true

  Check leadership for an alternate instance named `Oban.Private`:

      Oban.Peer.leader?(Oban.Private)
      # => true
  """
  @spec leader?(conf_or_name(), timeout()) :: boolean()
  def leader?(conf_or_name \\ Oban, timeout \\ 5_000) do
    safe_call(conf_or_name, :leader?, timeout, false)
  end

  defp safe_call(%Config{name: name, peer: {peer, _}}, fun, timeout, default) do
    case Registry.whereis(name, Oban.Peer) do
      pid when is_pid(pid) ->
        apply(peer, fun, [pid, timeout])

      _ ->
        default
    end
  catch
    :exit, {:timeout, _} = reason ->
      Logger.warning(
        message: "Oban.Peer.#{fun}/2 check failed due to #{inspect(reason)}",
        source: :oban,
        module: __MODULE__
      )

      default
  end

  defp safe_call(name, fun, timeout, default) do
    name
    |> Oban.config()
    |> safe_call(fun, timeout, default)
  end
end
