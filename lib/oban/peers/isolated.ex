defmodule Oban.Peers.Isolated do
  @moduledoc false

  @behaviour Oban.Peer

  @impl Oban.Peer
  def start_link(opts) do
    leader? = Keyword.get(opts, :leader?, true)

    Agent.start_link(fn -> leader? end, name: opts[:name])
  end

  @impl Oban.Peer
  def leader?(pid, timeout \\ 5000), do: Agent.get(pid, & &1, timeout)
end
