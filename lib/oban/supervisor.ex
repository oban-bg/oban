defmodule Oban.Supervisor do
  @moduledoc false

  use Supervisor

  alias Oban.Config

  @doc false
  @spec start_link(Keyword.t()) :: Supervisor.on_start()
  def start_link(opts) when is_list(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)

    Supervisor.start_link(__MODULE__, Config.new(opts), name: name)
  end

  @impl Supervisor
  def init(conf) do
    children = [
      {Config, conf: conf, name: conf.config_name},
      {conf.database, conf: conf, name: conf.database_name}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
