defmodule Oban.Plugins.Repeater do
  @moduledoc """
  Forced polling mode for local queues.

  This plugin is superseded by `Oban.Plugins.Stager`.
  """

  @moduledoc deprecated: "See Oban.Plugins.Stager"

  @behaviour Oban.Plugin

  use GenServer

  alias Oban.Plugin

  require Logger

  @impl Plugin
  def start_link(_opts) do
    Logger.warn("""
    Repeater is deprecated.

    Stager automatically forces polling when notifications aren't available. You can safely remove
    the Repeater from your plugins.
    """)

    GenServer.start_link(__MODULE__, [])
  end

  @impl Plugin
  def validate(_opts), do: :ok

  @impl GenServer
  def init(_opts), do: :ignore
end
