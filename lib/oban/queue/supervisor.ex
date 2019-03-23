defmodule Oban.Queue.Supervisor do
  @moduledoc false

  use Supervisor

  alias Oban.Config
  alias Oban.Queue.{Producer, Watchman}
  alias Postgrex.Notifications

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

  @impl Supervisor
  def init(conf: conf, queue: queue, limit: limit, name: name) do
    fore_name = Module.concat([name, "Foreman"])
    note_name = Module.concat([name, "Notifier"])
    prod_name = Module.concat([name, "Producer"])

    fore_opts = [strategy: :one_for_one, name: fore_name]

    prod_opts = [
      conf: conf,
      foreman: fore_name,
      limit: limit,
      notifier: note_name,
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
      {DynamicSupervisor, fore_opts},
      notifier_spec(Keyword.put(conf.repo.config(), :name, note_name)),
      {Producer, prod_opts},
      {Watchman, watch_opts}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end

  # Postgrex.Notifications doesn't support `child_spec/1`, so we have to define it ourselves.
  defp notifier_spec(opts) do
    %{id: Notifications, start: {Notifications, :start_link, [opts]}}
  end
end
