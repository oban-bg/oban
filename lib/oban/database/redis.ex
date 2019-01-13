defmodule Oban.Database.Redis do
  @moduledoc false

  @behaviour Oban.Database

  alias Oban.{Config, Job}

  @impl Oban.Database
  def start_link(opts) do
    {host, opts} = Keyword.pop(opts, :redis_url)

    # initialize afterwards

    Redix.start_link(host, exit_on_disconnection: true)
  end

  def init(db, %Config{ident: ident, streams: streams}) do
    commands = for stream <- streams do
      ["XGROUP", "CREATE", stream, group_name(ident, stream), "$", "MKSTREAM"]
    end

    # If the group already exists this will cause a "BUSYGROUP" error, we don't want to raise
    # here.
    Redix.pipeline!(db, commands)

    # This is also the point where we need to claim dead entries
  end

  @impl Oban.Database
  def push(db, %Job{stream: stream} = job, %Config{maxlen: maxlen}) do
    # The id value is either the * character or a future timestamp
    command = ["XADD", stream, "MAXLEN", "~", maxlen, "*"] ++ Job.to_fields(job)

    %{job | id: Redix.command!(db, command)}
  end

  @impl Oban.Database
  def pull(db, stream, limit, %Config{group: group, ident: ident}) when is_binary(stream) and limit > 0 do
    # Somehow we need to get new values UP TO the given ID. XRANGE can give us the values, but
    # doesn't count as reading for a consumer group.
    # What is the consumer name? That needs to be specific for this node/dyno type thing.
    ["XREADGROUP", "GROUP", group, "ALICE"]
    ["COUNT", limit, "BLOCK", "1000"] # NOTE: Don't hardcode this value
    ["STREAMS", stream, "ID", "$"]

    case Redix.command!(db, []) do
      [_stream, entries] -> [:do_something]
      nil -> []
    end
  end

  @impl Oban.Database
  def ack(db, stream, id, %Config{group: group}) when is_binary(id) do
    Redix.command!(db, ["XACK", stream, group, id])
  end

  # Helpers

  defp group_name(ident, stream), do: "#{ident}:#{stream}"
end
