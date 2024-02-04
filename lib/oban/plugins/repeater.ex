defmodule Oban.Plugins.Repeater do
  @moduledoc false

  @behaviour Oban.Plugin

  use GenServer

  alias Oban.Plugin

  require Logger

  @impl Plugin
  def start_link(_opts) do
    Logger.warning("""
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
