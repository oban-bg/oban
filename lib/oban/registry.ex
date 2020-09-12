defmodule Oban.Registry do
  @moduledoc false

  def child_spec(_arg) do
    Supervisor.child_spec(
      Registry.child_spec(keys: :unique, name: __MODULE__),
      id: __MODULE__
    )
  end

  def whereis(root_process, role), do: GenServer.whereis(via(root_process, role))

  def via(oban_name, role), do: {:via, Registry, {__MODULE__, {oban_name, role}}}
end
