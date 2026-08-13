defmodule Oban.Harbor do
  @moduledoc false

  use Supervisor

  alias Oban.{Config, Registry}

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

    children = stager_child_spec(conf) ++ Enum.map(conf.plugins, &plugin_child_spec(&1, conf))

    Supervisor.init(children, max_restarts: 5, max_seconds: 60, strategy: :one_for_one)
  end

  defp stager_child_spec(%Config{stager: {module, opts}} = conf) do
    opts = Keyword.merge(opts, conf: conf, name: Registry.via(conf.name, module))

    [{module, opts}]
  end

  defp stager_child_spec(_conf), do: []

  defp plugin_child_spec({module, opts}, conf) do
    name = Registry.via(conf.name, {:plugin, module})
    opts = Keyword.merge(opts, conf: conf, name: name)

    Supervisor.child_spec({module, opts}, id: {:plugin, module})
  end
end
