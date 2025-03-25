defmodule Oban.Midwife do
  @moduledoc false

  use GenServer

  alias Oban.{Config, Notifier, Queue, Registry}
  alias __MODULE__, as: State

  require Logger

  defstruct [:conf]

  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)

    GenServer.start_link(__MODULE__, struct!(State, opts), name: name)
  end

  @spec start_queue(Config.t(), Keyword.t() | {String.t(), Keyword.t()}) ::
          DynamicSupervisor.on_start_child()
  def start_queue(conf, opts) when is_list(opts) do
    queue =
      opts
      |> Keyword.fetch!(:queue)
      |> to_string()

    opts =
      opts
      |> Keyword.put(:conf, conf)
      |> Keyword.put(:queue, queue)
      |> Keyword.put(:name, Registry.via(conf.name, {:queue, queue}))

    conf
    |> foreman()
    |> DynamicSupervisor.start_child({Queue.Supervisor, opts})
  end

  def start_queue(conf, {queue, opts}) do
    opts
    |> Keyword.put(:queue, queue)
    |> then(&start_queue(conf, &1))
  end

  @spec stop_queue(Config.t(), atom() | String.t()) :: :ok | {:error, :not_found}
  def stop_queue(conf, queue) do
    case Registry.whereis(conf.name, {:queue, queue}) do
      pid when is_pid(pid) ->
        conf
        |> foreman()
        |> DynamicSupervisor.terminate_child(pid)

      nil ->
        {:error, :not_found}
    end
  end

  @impl GenServer
  def init(state) do
    state.conf.queues
    |> Task.async_stream(fn opts -> {:ok, _} = start_queue(state.conf, opts) end)
    |> Stream.run()

    {:ok, state, {:continue, :start}}
  end

  @impl GenServer
  def handle_continue(:start, %State{conf: conf} = state) do
    Notifier.listen(conf.name, :signal)

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:notification, :signal, payload}, %State{conf: conf} = state) do
    case payload do
      %{"action" => "start"} ->
        opts =
          payload
          |> Map.drop(["action", "ident", "local_only"])
          |> Keyword.new(fn {key, val} -> {String.to_existing_atom(key), val} end)

        start_queue(conf, opts)

      %{"action" => "stop", "queue" => queue} ->
        stop_queue(conf, queue)

      _ ->
        :ok
    end

    {:noreply, state}
  end

  def handle_info(message, state) do
    Logger.warning(
      message: "Received unexpected message: #{inspect(message)}",
      source: :oban,
      module: __MODULE__
    )

    {:noreply, state}
  end

  defp foreman(conf), do: Registry.via(conf.name, Foreman)
end
