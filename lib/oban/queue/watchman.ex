defmodule Oban.Queue.Watchman do
  @moduledoc false

  use GenServer

  alias Oban.Queue.{Consumer, Producer}

  @type option ::
          {:name, module()}
          | {:consumer, identifier()}
          | {:producer, identifier()}
          | {:shutdown, timeout()}

  defmodule State do
    @moduledoc false

    defstruct [:consumer, :producer]
  end

  @spec child_spec([option]) :: Supervisor.child_spec()
  def child_spec(opts) do
    {down, opts} = Keyword.pop(opts, :shutdown)

    %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}, shutdown: down}
  end

  @spec start_link([option]) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)

    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl GenServer
  def init(consumer: consumer, producer: producer) do
    Process.flag(:trap_exit, true)

    {:ok, %State{consumer: consumer, producer: producer}}
  end

  @impl GenServer
  def terminate(_reason, %State{consumer: consumer, producer: producer}) do
    :ok = Producer.pause(producer)
    :ok = Consumer.wait_for_executing(consumer)

    :ok
  end
end
