defmodule Oban.Registry do
  @moduledoc false

  @type role :: term
  @type key :: Oban.name() | {Oban.name(), role}

  def child_spec(_arg) do
    Supervisor.child_spec(
      Registry.child_spec(keys: :unique, name: __MODULE__),
      id: __MODULE__
    )
  end

  @spec whereis(Oban.name(), role) :: pid | nil
  def whereis(oban_name, role \\ nil), do: GenServer.whereis(via(oban_name, role))

  @spec via(Oban.name(), role) :: {:via, Registry, {__MODULE__, key}}
  def via(oban_name, role \\ nil), do: {:via, Registry, {__MODULE__, key(oban_name, role)}}

  defp key(oban_name, nil), do: oban_name
  defp key(oban_name, role), do: {oban_name, role}
end
