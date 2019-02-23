defmodule Oban.Queue.Consumer do
  @moduledoc false

  use ConsumerSupervisor

  alias Oban.Config
  alias Oban.Queue.Executor

  @type option ::
          {:name, module()}
          | {:conf, Config.t()}
          | GenStage.consumer_and_producer_consumer_option()

  @spec start_link([option]) :: Supervisor.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)

    ConsumerSupervisor.start_link(__MODULE__, opts, name: name)
  end

  @spec wait_for_executing(Supervisor.name(), pos_integer()) :: :ok
  def wait_for_executing(consumer, interval \\ 50) do
    # There is a chance that the consumer process doesn't exist, and we never want to raise
    # another error as part of the shut down process.
    children =
      try do
        ConsumerSupervisor.count_children(consumer)
      catch
        _ -> %{active: 0}
      end

    case children do
      %{active: 0} ->
        :ok

      _ ->
        :ok = Process.sleep(interval)

        wait_for_executing(consumer, interval)
    end
  end

  @impl ConsumerSupervisor
  def init(conf: conf, subscribe_to: subscribe_to) do
    children = [{Executor, conf: conf}]

    ConsumerSupervisor.init(children, strategy: :one_for_one, subscribe_to: subscribe_to)
  end
end
