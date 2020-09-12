defmodule Oban.Registry do
  @moduledoc false

  def child_spec(_arg) do
    Supervisor.child_spec(
      Registry.child_spec(keys: :unique, name: __MODULE__),
      id: __MODULE__
    )
  end

  def whereis(oban_name, role \\ nil), do: GenServer.whereis(via(oban_name, role))

  def via(oban_name, role \\ nil), do: {:via, Registry, {__MODULE__, key(oban_name, role)}}

  defp key(oban_name, nil), do: oban_name
  defp key(oban_name, role), do: {oban_name, role}
end
