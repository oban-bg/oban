defmodule Oban.Nursery do
  @moduledoc false

  use Supervisor

  alias Oban.{Config, Midwife, Registry}

  @type opts :: [conf: Config.t(), name: GenServer.name()]

  @spec start_link(opts()) :: Supervisor.on_start()
  def start_link(opts) when is_list(opts) do
    Supervisor.start_link(__MODULE__, opts, name: opts[:name])
  end

  @spec child_spec(opts()) :: Supervisor.child_spec()
  def child_spec(opts) do
    name = Keyword.fetch!(opts, :name)

    %{super(opts) | id: name}
  end

  @impl Supervisor
  def init(opts) do
    conf = Keyword.fetch!(opts, :conf)
    fore_name = Registry.via(conf.name, Foreman)
    wife_name = Registry.via(conf.name, Midwife)

    children = [
      {DynamicSupervisor, name: fore_name, max_restarts: 20, max_seconds: 60},
      {Midwife, conf: conf, name: wife_name}
    ]

    Supervisor.init(children, max_restarts: 5, max_seconds: 30, strategy: :rest_for_one)
  end
end
