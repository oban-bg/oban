defmodule Oban.Registry do
  @moduledoc false

  def child_spec(_arg) do
    Supervisor.child_spec(
      Registry.child_spec(keys: :unique, name: __MODULE__),
      id: __MODULE__
    )
  end

  def whereis(root_process, role), do: GenServer.whereis(via(root_process, role))

  def via(root_process, role) do
    root_pid = GenServer.whereis(root_process)
    {:via, Registry, {__MODULE__, {root_pid, role}}}
  end
end
