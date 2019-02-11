defmodule Oban.Queue.Supervisor do
  @moduledoc false

  use Supervisor

  alias Oban.Queue.{Consumer, Producer}

  @spec start_link(Keyword.t()) :: Supervisor.on_start()
  def start_link(opts) when is_list(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)

    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  @impl Supervisor
  def init(conf: conf, queue: queue, limit: limit) do
    prod_name = child_name(queue, "Producer")
    cons_name = child_name(queue, "Consumer")

    prod_opts = [conf: conf, queue: queue, name: prod_name]

    cons_opts = [
      conf: conf,
      subscribe_to: [{prod_name, max_demand: limit}],
      name: cons_name
    ]

    children = [
      {Producer, prod_opts},
      {Consumer, cons_opts}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end

  defp child_name(queue, name) do
    Module.concat(["Oban", "Queue", String.capitalize(queue), name])
  end
end
