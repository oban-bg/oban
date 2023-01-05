defmodule Oban.Peers.Isolated do
  @moduledoc false

  @behaviour Oban.Peer

  @impl Oban.Peer
  def start_link(opts) do
    Agent.start_link(fn -> true end, name: opts[:name])
  end

  @impl Oban.Peer
  def leader?(_pid, _timeout \\ nil), do: true
end
