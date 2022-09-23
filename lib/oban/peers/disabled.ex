defmodule Oban.Peers.Disabled do
  @moduledoc false

  @behaviour Oban.Peer

  @impl Oban.Peer
  def start_link(opts) do
    Agent.start_link(fn -> false end, name: opts[:name])
  end

  @impl Oban.Peer
  def leader?(_pid, _timeout \\ nil), do: false
end
