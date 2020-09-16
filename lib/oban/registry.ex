defmodule Oban.Registry do
  @moduledoc false

  @type role :: term()
  @type key :: Oban.name() | {Oban.name(), role()}
  @type value :: term()

  def child_spec(_arg) do
    [keys: :unique, name: __MODULE__]
    |> Registry.child_spec()
    |> Supervisor.child_spec(id: __MODULE__)
  end

  @spec config(Oban.name()) :: Oban.Config.t()
  def config(oban_name) do
    [{_pid, config}] = Registry.lookup(__MODULE__, oban_name)

    config
  end

  @spec whereis(Oban.name(), role()) :: pid() | nil
  def whereis(oban_name, role \\ nil) do
    oban_name
    |> via(role)
    |> GenServer.whereis()
  end

  @spec via(Oban.name(), role(), value()) :: {:via, Registry, {__MODULE__, key()}}
  def via(oban_name, role \\ nil, value \\ nil)
  def via(oban_name, role, nil), do: {:via, Registry, {__MODULE__, key(oban_name, role)}}
  def via(oban_name, role, value), do: {:via, Registry, {__MODULE__, key(oban_name, role), value}}

  defp key(oban_name, nil), do: oban_name
  defp key(oban_name, role), do: {oban_name, role}
end
