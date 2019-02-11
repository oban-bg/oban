defmodule Oban.Queue.Consumer do
  @moduledoc false

  use ConsumerSupervisor

  alias Oban.Queue.Executor

  @spec start_link(Keyword.t()) :: Supervisor.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)

    ConsumerSupervisor.start_link(__MODULE__, opts, name: name)
  end

  @impl ConsumerSupervisor
  def init(conf: conf, subscribe_to: subscribe_to) do
    children = [{Executor, conf: conf}]

    ConsumerSupervisor.init(children, strategy: :one_for_one, subscribe_to: subscribe_to)
  end
end
