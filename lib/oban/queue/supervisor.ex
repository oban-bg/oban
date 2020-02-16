defmodule Oban.Queue.Supervisor do
  @moduledoc false

  use Supervisor

  alias Oban.Config
  alias Oban.Queue.{Producer, Watchman}

  @type option ::
          {:name, module()}
          | {:conf, Config.t()}
          | {:queue, binary()}
          | {:limit, pos_integer()}

  @spec start_link([option]) :: Supervisor.on_start()
  def start_link(opts) when is_list(opts) do
    name = Keyword.get(opts, :name, __MODULE__)

    Supervisor.start_link(__MODULE__, Map.new(opts), name: name)
  end

  @spec child_spec({atom(), integer()}, Config.t()) :: Supervisor.child_spec()
  def child_spec({queue, limit}, conf) do
    queue = to_string(queue)
    name = Module.concat([conf.name, "Queue", Macro.camelize(queue)])
    opts = [conf: conf, queue: queue, limit: limit, name: name]

    Supervisor.child_spec({__MODULE__, opts}, id: name)
  end

  @impl Supervisor
  def init(%{conf: conf, limit: limit, name: name, queue: queue}) do
    fore_name = Module.concat([name, "Foreman"])
    prod_name = Module.concat([name, "Producer"])

    fore_opts = [name: fore_name]

    prod_opts = [
      conf: conf,
      foreman: fore_name,
      limit: limit,
      queue: queue,
      name: prod_name
    ]

    watch_opts = [
      foreman: fore_name,
      name: Module.concat([name, "Watchman"]),
      producer: prod_name,
      shutdown: conf.shutdown_grace_period
    ]

    children = [
      {Task.Supervisor, fore_opts},
      {Producer, prod_opts},
      {Watchman, watch_opts}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
