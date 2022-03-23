defmodule Oban.Peer do
  @moduledoc """
  The `Peer` module maintains leadership for a particular Oban instance within a cluster.

  Leadership is used by plugins, primarily, to prevent duplicate work accross nodes. For example,
  only the leader's `Cron` plugin will insert new jobs. You can use peer leadership to extend Oban
  with custom plugins, or even within your own application.

  Note a few important details about how peer leadership operates:

  * Each peer checks for leadership at a 30 second interval. When the leader exits it broadcasts a
    message to all other peers to encourage another one to assume leadership.

  * Each Oban instances supervises a distinct `Oban.Peer` instance. That means that with multiple
    Oban instances on the same node one instance may be the leader, while the others aren't.

  * Without leadership, global plugins (Cron, Lifeline, Stager, etc.), will not run on any node.

  ## Available Peer Implementations

  There are two built-in peering modules:

  * `Oban.Peers.Postgres` — uses table-based leadership through the `oban_peers` table and works
    in any environment, with or without clustering. This is the default.

  * `Oban.Peers.Global` — coordinates global locks through distributed Erlang, requires
    distributed Erlang.

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

  @type option ::
          {:name, module()}
          | {:conf, Config.t()}
          | {:interval, timeout()}

  @doc """
  Starts a peer instance.
  """
  @callback start_link([option()]) :: GenServer.on_start()

  @doc """
  Check whether the current peer instance leads the cluster.
  """
  @callback leader?(pid()) :: boolean()

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
  @spec leader?(Config.t() | GenServer.server()) :: boolean()
  def leader?(conf_or_name \\ Oban)

  def leader?(%Config{} = conf) do
    case Registry.whereis(conf.name, Oban.Peer) do
      pid when is_pid(pid) ->
        conf.peer.leader?(pid)

      nil ->
        false
    end
  end

  def leader?(name) do
    name
    |> Oban.config()
    |> leader?()
  end

  @doc false
  @spec child_spec(Keyword.t()) :: Supervisor.child_spec()
  def child_spec(opts) do
    conf = Keyword.fetch!(opts, :conf)
    opts = Keyword.put_new(opts, :name, conf.peer)

    %{id: opts[:name], start: {conf.peer, :start_link, [opts]}}
  end
end
