defmodule Oban.Queue.Watchman do
  @moduledoc false

  use GenServer

  alias Oban.Queue.Producer

  @type option ::
          {:name, module()}
          | {:foreman, identifier()}
          | {:producer, identifier()}
          | {:shutdown, timeout()}

  defmodule State do
    @moduledoc false

    defstruct [:foreman, :producer, :shutdown]
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

    GenServer.start_link(__MODULE__, Map.new(opts), name: name)
  end

  @impl GenServer
  def init(%{foreman: foreman, producer: producer}) do
    Process.flag(:trap_exit, true)

    {:ok, %State{foreman: foreman, producer: producer}}
  end

  @impl GenServer
  def terminate(_reason, %State{foreman: foreman, producer: producer}) do
    try do
      :ok = Producer.shutdown(producer)
      :ok = wait_for_executing(foreman)
    catch
      :exit, _reason -> :ok
    end

    :ok
  end

  defp wait_for_executing(foreman, interval \\ 50) do
    # There is a chance that the consumer process doesn't exist, and we never want to raise
    # another error as part of the shut down process.
    children =
      try do
        Supervisor.count_children(foreman)
      catch
        _ -> %{active: 0}
      end

    case children do
      %{active: 0} ->
        :ok

      _ ->
        :ok = Process.sleep(interval)

        wait_for_executing(foreman, interval)
    end
  end
end
