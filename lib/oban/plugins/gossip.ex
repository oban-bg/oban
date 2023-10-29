defmodule Oban.Plugins.Gossip do
  @moduledoc """
  Periodic replication of queue state information between nodes.
  """

  @moduledoc deprecated: "Superseded by external metrics and no longer required for `Oban.Web`"

  @behaviour Oban.Plugin

  use GenServer

  alias Oban.Plugin

  require Logger

  @impl Plugin
  def start_link(_opts) do
    Logger.warning("""
    Gossip is deprecated.

    Gossip is no longer needed for queue monitoring in Oban Web. You can safely remove Gossip from
    your plugins.
    """)

    GenServer.start_link(__MODULE__, [])
  end

  @impl Plugin
  def validate(_opts), do: :ok

  @impl GenServer
  def init(_opts), do: :ignore
end
