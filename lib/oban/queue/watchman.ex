defmodule Oban.Queue.Watchman do
  @moduledoc false

  use GenServer

  alias Oban.Queue.Producer

  @type option ::
          {:foreman, GenServer.name()}
          | {:name, module()}
          | {:producer, GenServer.name()}
          | {:shutdown, timeout()}

  defmodule State do
    @moduledoc false

    defstruct [:foreman, :producer, :shutdown, interval: 10]
  end

  @spec child_spec([option]) :: Supervisor.child_spec()
  def child_spec(opts) do
    shutdown =
      case opts[:shutdown] do
        0 ->
          :brutal_kill

        value ->
          value
      end

    %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}, shutdown: shutdown}
  end

  @spec start_link([option]) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)

    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl GenServer
  def init(opts) do
    Process.flag(:trap_exit, true)

    {:ok, struct!(State, opts)}
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
