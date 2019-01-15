defmodule Oban.Database.Memory do
  @moduledoc false

  use GenServer

  alias Oban.{Config, Job}

  @behaviour Oban.Database

  @impl Oban.Database
  def start_link(opts) do
    name = Keyword.get(opts, :name)
    conf = Keyword.get(opts, :conf)

    GenServer.start_link(__MODULE__, conf, name: name)
  end

  # Database Callbacks

  @impl Oban.Database
  def push(_db, %Job{} = job, %Config{} = conf) do
    jid = System.unique_integer([:positive, :monotonic])
    job = %{job | id: jid}

    true = :ets.insert(queue_table(conf), {{job.queue, job.id}, job})

    job
  end

  @impl Oban.Database
  def pull(_db, queue, limit, conf) when is_binary(queue) and limit > 0 do
    queue_table = queue_table(conf)
    claim_table = claim_table(conf)

    reducer = fn {key, job}, acc ->
      case :ets.take(queue_table, key) do
        [{^key, ^job}] ->
          :ets.insert(claim_table, {key, job})

          [job | acc]

        [] ->
          acc
      end
    end

    case :ets.select(queue_table, [{{{queue, :_}, :_}, [], [:"$_"]}], limit) do
      {matches, _cont} ->
        matches
        |> Enum.reduce([], reducer)
        |> Enum.reverse()

      _ ->
        []
    end
  end

  @impl Oban.Database
  def peek(_db, queue, limit, nil, conf) when is_binary(queue) and limit > 0 do
    case :ets.select(queue_table(conf), [{{{queue, :_}, :"$1"}, [], [:"$1"]}], limit) do
      {_matches, _cont} = result -> result
      _ -> []
    end
  end

  def peek(_db, _queue, _limit, cont, _conf) do
    case :ets.select(cont) do
      {_matches, _cont} = result -> result
      _ -> []
    end
  end


  @impl Oban.Database
  def ack(_db, queue, id, conf) when is_binary(queue) and is_integer(id) do
    case :ets.select_delete(claim_table(conf), [{{{queue, id}, :_}, [], [true]}]) do
      1 -> true
      0 -> false
    end
  end

  @impl Oban.Database
  def restore(_db, queue, id, conf) when is_binary(queue) and is_integer(id) do
    case :ets.take(claim_table(conf), {queue, id}) do
      [{key, job}] ->
        :ets.insert(queue_table(conf), {key, job})

      [] ->
        false
    end
  end

  @impl Oban.Database
  def clear(_db, conf) do
    true = :ets.delete_all_objects(claim_table(conf))
    true = :ets.delete_all_objects(queue_table(conf))

    :ok
  end

  # GenServer Callbacks

  @impl GenServer
  def init(%Config{} = conf) do
    maybe_create_table(claim_table(conf))
    maybe_create_table(queue_table(conf))

    {:ok, nil}
  end

  # Helpers

  defp claim_table(%Config{main: main}), do: Module.concat([main, "Claim"])

  defp queue_table(%Config{main: main}), do: Module.concat([main, "queues"])

  defp maybe_create_table(table_name) do
    case :ets.whereis(table_name) do
      :undefined -> :ets.new(table_name, [:ordered_set, :public, :named_table])
      _ -> :ok
    end
  end
end
