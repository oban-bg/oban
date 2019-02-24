defmodule Oban.Queue.Supervisor do
  @moduledoc false

  use Supervisor

  alias Oban.Config
  alias Oban.Queue.{Consumer, Producer, Watchman}

  @type option ::
          {:name, module()}
          | {:conf, Config.t()}
          | {:queue, binary()}
          | {:limit, pos_integer()}

  @spec start_link([option]) :: Supervisor.on_start()
  def start_link(opts) when is_list(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)

    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  @impl Supervisor
  def init(conf: conf, queue: queue, limit: limit) do
    prod_name = child_name(conf.name, queue, "Producer")
    cons_name = child_name(conf.name, queue, "Consumer")

    prod_opts = [conf: conf, queue: queue, name: prod_name]

    cons_opts = [
      conf: conf,
      name: cons_name,
      subscribe_to: [{prod_name, max_demand: limit}]
    ]

    watch_opts = [
      consumer: cons_name,
      name: child_name(conf.name, queue, "Watchman"),
      producer: prod_name,
      shutdown: conf.shutdown_grace_period
    ]

    children = [
      {Producer, prod_opts},
      {Consumer, cons_opts},
      {Watchman, watch_opts}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end

  defp child_name(base, queue, name) do
    Module.concat([base, "Queue", String.capitalize(queue), name])
  end
end
