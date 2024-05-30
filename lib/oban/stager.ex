defmodule Oban.Stager do
  @moduledoc false

  use GenServer

  import Ecto.Query, only: [distinct: 2, select: 3, where: 3]

  alias Oban.{Engine, Job, Notifier, Peer, Plugin, Repo}
  alias __MODULE__, as: State

  @type option :: Plugin.option() | {:interval, pos_integer()}

  defstruct [
    :conf,
    :timer,
    interval: :timer.seconds(1),
    limit: 5_000,
    mode: :global
  ]

  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)

    conf = Keyword.fetch!(opts, :conf)

    if conf.stage_interval == :infinity do
      :ignore
    else
      state = %State{conf: conf, interval: conf.stage_interval}

      GenServer.start_link(__MODULE__, state, name: name)
    end
  end

  @impl GenServer
  def init(state) do
    Process.flag(:trap_exit, true)

    # Init event is essential for auto-allow and backward compatibility.
    :telemetry.execute([:oban, :plugin, :init], %{}, %{conf: state.conf, plugin: __MODULE__})

    {:ok, schedule_staging(state)}
  end

  @impl GenServer
  def terminate(_reason, %State{timer: timer}) do
    if is_reference(timer), do: Process.cancel_timer(timer)

    :ok
  end

  @impl GenServer
  def handle_info(:stage, %State{} = state) do
    state = check_mode(state)
    meta = %{conf: state.conf, leader: Peer.leader?(state.conf), plugin: __MODULE__}

    :telemetry.span([:oban, :plugin], meta, fn ->
      case stage_and_notify(meta.leader, state) do
        {:ok, staged} ->
          {:ok, Map.merge(meta, %{staged_count: length(staged), staged_jobs: staged})}

        {:error, error} ->
          {:error, Map.put(meta, :error, error)}
      end
    end)

    {:noreply, schedule_staging(state)}
  end

  defp stage_and_notify(true = _leader, state) do
    Repo.transaction(state.conf, fn ->
      {:ok, staged} = Engine.stage_jobs(state.conf, Job, limit: state.limit)

      notify_queues(state)

      staged
    end)
  rescue
    error in [DBConnection.ConnectionError, Postgrex.Error] -> {:error, error}
  end

  defp stage_and_notify(_leader, state) do
    if state.mode == :local, do: notify_queues(state)

    {:ok, []}
  end

  defp notify_queues(%{conf: conf, mode: :global}) do
    query =
      Job
      |> where([j], j.state == "available")
      |> where([j], not is_nil(j.queue))
      |> select([j], %{queue: j.queue})
      |> distinct(true)

    payload = Repo.all(conf, query)

    Notifier.notify(conf, :insert, payload)
  end

  defp notify_queues(%{conf: conf, mode: :local}) do
    match = [{{{conf.name, {:producer, :"$1"}}, :"$2", :_}, [], [{{:"$1", :"$2"}}]}]

    for {queue, pid} <- Registry.select(Oban.Registry, match) do
      send(pid, {:notification, :insert, %{"queue" => queue}})
    end

    :ok
  end

  # Helpers

  defp schedule_staging(state) do
    timer = Process.send_after(self(), :stage, state.interval)

    %{state | timer: timer}
  end

  defp check_mode(state) do
    next_mode =
      case Notifier.status(state.conf) do
        :clustered -> :global
        :isolated -> :local
        :solitary -> if Peer.leader?(state.conf), do: :global, else: :local
        :unknown -> state.mode
      end

    if state.mode != next_mode do
      :telemetry.execute([:oban, :stager, :switch], %{}, %{conf: state.conf, mode: next_mode})
    end

    %{state | mode: next_mode}
  end
end
