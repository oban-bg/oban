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
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)

    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  @impl Supervisor
  def init(conf: conf, queue: queue, limit: limit) do
    fore_name = child_name(conf.name, queue, "Foreman")
    prod_name = child_name(conf.name, queue, "Producer")

    fore_opts = [strategy: :one_for_one, name: fore_name]
    prod_opts = [conf: conf, foreman: fore_name, limit: limit, queue: queue, name: prod_name]

    watch_opts = [
      foreman: fore_name,
      name: child_name(conf.name, queue, "Watchman"),
      producer: prod_name,
      shutdown: conf.shutdown_grace_period
    ]

    children = [
      {DynamicSupervisor, fore_opts},
      {Producer, prod_opts},
      {Watchman, watch_opts}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end

  defp child_name(base, queue, name) do
    Module.concat([base, "Queue", String.capitalize(queue), name])
  end
end
