defmodule Oban.Supervisor do
  @moduledoc false

  use Supervisor

  alias Oban.Config
  alias Oban.Queue.Supervisor, as: QueueSupervisor

  @spec start_link(Keyword.t()) :: Supervisor.on_start()
  def start_link(opts) when is_list(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)

    Supervisor.start_link(__MODULE__, Config.new(opts), name: name)
  end

  @impl Supervisor
  def init(%Config{queues: queues} = conf) do
    children = Enum.map(queues, &queue_spec(&1, conf))

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp queue_spec({queue, limit}, conf) do
    queue = to_string(queue)
    name = Module.concat(["Oban", "Queue", String.capitalize(queue)])
    opts = [conf: conf, queue: queue, limit: limit, name: name]

    Supervisor.child_spec({QueueSupervisor, opts}, id: name)
  end
end
