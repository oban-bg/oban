defmodule Oban.Database.Redis do
  @moduledoc false

  @behaviour Oban.Database

  alias Oban.{Config, Job}

  @impl Oban.Database
  def start_link(opts) do
    {host, _opts} = Keyword.pop(opts, :redis_url)

    # initialize afterwards

    Redix.start_link(host, exit_on_disconnection: true)
  end

  def init(db, %Config{main: main, queues: queues}) do
    commands = for {queue, _} <- queues do
      ["XGROUP", "CREATE", queue, group_name(main, queue), "$", "MKSTREAM"]
    end

    # If the group already exists this will cause a "BUSYGROUP" error, we don't want to raise
    # here.
    Redix.pipeline!(db, commands)

    # This is also the point where we need to claim dead entries
  end

  @impl Oban.Database
  def push(db, %Job{queue: queue} = job, %Config{}) do
    # The id value is either the * character or a future timestamp
    command = ["XADD", queue, "MAXLEN", "~", "10000", "*"] ++ Job.to_fields(job)

    %{job | id: Redix.command!(db, command)}
  end

  @impl Oban.Database
  def pull(db, queue, limit, %Config{main: main, node: node}) when is_binary(queue) and limit > 0 do
    # Somehow we need to get new values UP TO the given ID. XRANGE can give us the values, but
    # doesn't count as reading for a consumer group.
    # What is the consumer name? That needs to be specific for this node/dyno type thing.
    ["XREADGROUP", "GROUP", group_name(main, queue), node]
    ["COUNT", limit, "BLOCK", "1000"] # NOTE: Don't hardcode this value
    ["STREAMS", queue, "ID", "$"]

    case Redix.command!(db, []) do
      [_queue, entries] -> [:do_something]
      nil -> []
    end
  end

  @impl Oban.Database
  def ack(db, queue, id, %Config{main: main}) when is_binary(id) do
    Redix.command!(db, ["XACK", queue, group_name(main, queue), id])
  end

  # Helpers

  defp group_name(main, queue), do: "#{main}:#{queue}"
end
