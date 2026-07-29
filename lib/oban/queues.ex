defmodule Oban.Queues do
  @moduledoc """
  Starts and stops the queues listed in the `:queues` option.

  This is the default queue implementation. It starts each configured queue when an instance
  starts, leaves them running until the instance stops, and manages queues on demand in response
  to `Oban.start_queue/2` and `Oban.stop_queue/2`.

  > #### 🌟 Oban Pro's Queues {: .info}
  >
  > Queues listed in the `:queues` option are static, and changes to concurrency at runtime are
  > lost on restart. To configure queues at runtime and persist those changes across restarts, see
  > [`Oban.Pro.Queues`](https://oban.pro/docs/pro/Oban.Pro.Queues.html).

  There's nothing to configure here directly. Queues are declared with the top level `:queues`
  option:

      config :my_app, Oban,
        queues: [default: 10, exports: 5],
        ...
  """

  use GenServer

  alias Oban.{Config, Notifier, Registry}
  alias Oban.Queues.Supervisor, as: QueueSupervisor
  alias __MODULE__, as: State

  require Logger

  defstruct [:conf, :notifier_ref, queues: []]

  @doc false
  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)

    GenServer.start_link(__MODULE__, struct!(State, opts), name: name)
  end

  @doc false
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
    |> DynamicSupervisor.start_child({QueueSupervisor, opts})
  end

  def start_queue(conf, {queue, opts}) do
    opts
    |> Keyword.put(:queue, queue)
    |> then(&start_queue(conf, &1))
  end

  @doc false
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
    state.queues
    |> Task.async_stream(fn opts -> {:ok, _} = start_queue(state.conf, opts) end)
    |> Stream.run()

    {:ok, state, {:continue, :start}}
  end

  @impl GenServer
  def handle_continue(:start, %State{conf: conf} = state) do
    Notifier.listen(conf.name, :signal)
    ref = monitor_notifier(conf)

    {:noreply, %{state | notifier_ref: ref}}
  end

  def handle_continue(:resubscribe, state) do
    resubscribe(state)
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

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %State{notifier_ref: ref} = state) do
    {:noreply, %{state | notifier_ref: nil}, {:continue, :resubscribe}}
  end

  def handle_info(:resubscribe, state) do
    resubscribe(state)
  end

  def handle_info(message, state) do
    Logger.warning(
      [
        message: "Received unexpected message: #{inspect(message)}",
        source: :oban,
        module: __MODULE__
      ],
      domain: [:oban]
    )

    {:noreply, state}
  end

  defp resubscribe(%State{conf: conf} = state) do
    case Registry.whereis(conf.name, Oban.Notifier) do
      pid when is_pid(pid) ->
        Notifier.listen(conf.name, :signal)

        {:noreply, %{state | notifier_ref: Process.monitor(pid)}}

      nil ->
        Process.send_after(self(), :resubscribe, 100)

        {:noreply, state}
    end
  end

  defp monitor_notifier(conf) do
    case Registry.whereis(conf.name, Oban.Notifier) do
      pid when is_pid(pid) -> Process.monitor(pid)
      nil -> nil
    end
  end

  defp foreman(conf), do: Registry.via(conf.name, Foreman)
end
