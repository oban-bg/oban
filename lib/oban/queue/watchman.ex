defmodule Oban.Queue.Watchman do
  @moduledoc false

  use GenServer

  alias Oban.Queue.Producer
  alias __MODULE__, as: State

  @type option ::
          {:foreman, GenServer.name()}
          | {:name, module()}
          | {:producer, GenServer.name()}
          | {:shutdown, timeout()}

  defstruct [:foreman, :producer, :shutdown, interval: 10]

  @spec child_spec([option]) :: Supervisor.child_spec()
  def child_spec(opts) do
    shutdown =
      case opts[:shutdown] do
        0 -> :brutal_kill
        value -> value
      end

    %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}, shutdown: shutdown}
  end

  @spec start_link([option]) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)

    GenServer.start_link(__MODULE__, struct!(State, opts), name: name)
  end

  @impl GenServer
  def init(state) do
    Process.flag(:trap_exit, true)

    {:ok, state}
  end

  @impl GenServer
  def terminate(_reason, %State{} = state) do
    # There is a chance that the foreman doesn't exist, and we never want to raise another error
    # as part of the shut down process.
    try do
      :ok = Producer.shutdown(state.producer)
      :ok = wait_for_executing(state)
    catch
      :exit, _reason -> :ok
    end

    :ok
  end

  defp wait_for_executing(state) do
    case DynamicSupervisor.count_children(state.foreman) do
      %{active: 0} ->
        :ok

      _ ->
        :ok = Process.sleep(state.interval)

        wait_for_executing(state)
    end
  end
end
