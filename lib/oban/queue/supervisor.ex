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

    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  @spec child_spec({atom(), integer()}, Config.t()) :: Supervisor.child_spec()
  def child_spec({queue, opts}, conf) do
    queue = to_string(queue)
    name = Module.concat([conf.name, "Queue", Macro.camelize(queue)])
    opts = Keyword.merge(opts, conf: conf, queue: queue, name: name)

    Supervisor.child_spec({__MODULE__, opts}, id: name)
  end

  @impl Supervisor
  def init(opts) do
    conf = Keyword.fetch!(opts, :conf)
    name = Keyword.fetch!(opts, :name)

    fore_name = Module.concat(name, "Foreman")
    prod_name = Module.concat(name, "Producer")
    watch_name = Module.concat(name, "Watchman")

    fore_opts = [name: fore_name]

    prod_opts =
      opts
      |> Keyword.take([:conf, :dispatch_cooldown, :limit, :poll_interval, :queue])
      |> Keyword.merge(foreman: fore_name, name: prod_name)
      |> Keyword.put_new(:dispatch_cooldown, conf.dispatch_cooldown)
      |> Keyword.put_new(:poll_interval, conf.poll_interval)

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

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
