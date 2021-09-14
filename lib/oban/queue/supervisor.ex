defmodule Oban.Queue.Supervisor do
  @moduledoc false

  use Supervisor

  alias Oban.{Config, Registry}
  alias Oban.Queue.{Producer, Watchman}

  @type option ::
          {:name, module()}
          | {:conf, Config.t()}
          | {:queue, binary()}
          | {:limit, pos_integer()}

  @type queue_name :: atom() | binary()
  @type queue_opts :: integer() | Keyword.t()

  @spec start_link([option]) :: Supervisor.on_start()
  def start_link(opts) when is_list(opts) do
    name = Keyword.get(opts, :name, __MODULE__)

    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  @spec child_spec({queue_name(), queue_opts()}, Config.t()) :: Supervisor.child_spec()
  def child_spec({queue, opts}, conf) do
    queue = to_string(queue)
    name = Registry.via(conf.name, {:supervisor, queue})
    opts = Keyword.merge(opts, conf: conf, queue: queue, name: name)

    Supervisor.child_spec({__MODULE__, opts}, id: queue)
  end

  @impl Supervisor
  def init(opts) do
    conf = Keyword.fetch!(opts, :conf)
    queue = Keyword.fetch!(opts, :queue)

    fore_name = Registry.via(conf.name, {:foreman, queue})
    prod_name = Registry.via(conf.name, {:producer, queue})
    watch_name = Registry.via(conf.name, {:watchman, queue})

    fore_opts = [name: fore_name]

    prod_opts =
      opts
      |> Keyword.drop([:name])
      |> Keyword.merge(foreman: fore_name, name: prod_name)
      |> Keyword.put_new(:dispatch_cooldown, conf.dispatch_cooldown)

    watch_opts = [
      foreman: fore_name,
      name: watch_name,
      producer: prod_name,
      shutdown: conf.shutdown_grace_period
    ]

    prod_mod = Keyword.get(opts, :producer, Producer)

    children = [
      {Task.Supervisor, fore_opts},
      {prod_mod, prod_opts},
      {Watchman, watch_opts}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
