defmodule Oban.Registry do
  @moduledoc """
  Local process storage for Oban instances.
  """

  @type role :: term()
  @type key :: Oban.name() | {Oban.name(), role()}
  @type value :: term()

  @doc false
  def child_spec(_arg) do
    [keys: :unique, name: __MODULE__]
    |> Registry.child_spec()
    |> Supervisor.child_spec(id: __MODULE__)
  end

  @doc """
  Fetch the config for an Oban supervisor instance.

  ## Example

  Get the default instance config:

      Oban.Registry.config(Oban)

  Get config for a custom named instance:

      Oban.Registry.config(MyApp.Oban)
  """
  @spec config(Oban.name()) :: Oban.Config.t()
  def config(oban_name) do
    case lookup(oban_name) do
      {_pid, config} ->
        config

      _ ->
        raise RuntimeError, """
        No Oban instance named `#{inspect(oban_name)}` is running and config isn't available.
        """
    end
  end

  @doc """
  Find the `{pid, value}` pair for a registered Oban process.

  ## Example

  Get the default instance config:

      Oban.Registry.lookup(Oban)

  Get a supervised module's pid:

      Oban.Registry.lookup(Oban, Oban.Notifier)
  """
  @spec lookup(Oban.name(), role()) :: nil | {pid(), value()}
  def lookup(oban_name, role \\ nil) do
    __MODULE__
    |> Registry.lookup(key(oban_name, role))
    |> List.first()
  end

  @doc """
  Returns the pid of a supervised Oban process, or `nil` if the process can't be found.

  ## Example

  Get the Oban supervisor's pid:

      Oban.Registry.whereis(Oban)

  Get a supervised module's pid:

      Oban.Registry.whereis(Oban, Oban.Notifier)

  Get the pid for a plugin:

      Oban.Registry.whereis(Oban, {:plugin, MyApp.Oban.Plugin})

  Get the pid for a queue's producer:

      Oban.Registry.whereis(Oban, {:producer, "default"})
  """
  @spec whereis(Oban.name(), role()) :: pid() | {atom(), node()} | nil
  def whereis(oban_name, role \\ nil) do
    oban_name
    |> via(role)
    |> GenServer.whereis()
  end

  @doc """
  Build a via tuple suitable for calls to a supervised Oban process.

  ## Example

  For an Oban supervisor:

      Oban.Registry.via(Oban)

  For a supervised module:

      Oban.Registry.via(Oban, Oban.Notifier)

  For a plugin:

      Oban.Registry.via(Oban, {:plugin, Oban.Plugins.Cron})
  """
  @spec via(Oban.name(), role(), value()) :: {:via, Registry, {__MODULE__, key()}}
  def via(oban_name, role \\ nil, value \\ nil)
  def via(oban_name, role, nil), do: {:via, Registry, {__MODULE__, key(oban_name, role)}}
  def via(oban_name, role, value), do: {:via, Registry, {__MODULE__, key(oban_name, role), value}}

  defp key(oban_name, nil), do: oban_name
  defp key(oban_name, role), do: {oban_name, role}
end
