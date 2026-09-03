defmodule Oban.Notifier.Registry do
  @moduledoc false

  alias Oban.Config

  @type channel :: Oban.Notifier.channel()

  def child_spec(_arg) do
    [keys: :duplicate, name: __MODULE__]
    |> Registry.child_spec()
    |> Supervisor.child_spec(id: __MODULE__)
  end

  @spec register(Config.t(), channel()) :: :ok
  def register(%Config{name: name}, channel) when is_atom(channel) do
    key = {name, channel}

    if Registry.values(__MODULE__, key, self()) == [] do
      Registry.register(__MODULE__, key, nil)
    end

    :ok
  end

  @spec unregister(Config.t(), channel()) :: :ok
  def unregister(%Config{name: name}, channel) when is_atom(channel) do
    Registry.unregister(__MODULE__, {name, channel})
  end

  @spec channels(Config.t()) :: [channel()]
  def channels(%Config{name: name}) do
    __MODULE__
    |> Registry.select([{{{name, :"$1"}, :_, :_}, [], [:"$1"]}])
    |> Enum.uniq()
  end

  @spec listeners(Config.t(), channel()) :: [pid()]
  def listeners(%Config{name: name}, channel) when is_atom(channel) do
    for {pid, _value} <- Registry.lookup(__MODULE__, {name, channel}), do: pid
  end
end
