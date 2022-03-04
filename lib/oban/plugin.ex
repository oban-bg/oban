defmodule Oban.Plugin do
  @moduledoc """
  Defines a shared behaviour for Oban plugins.

  In addition to implementing the Plugin behaviour, all plugins **must** be a GenServer, Agent, or
  another OTP compliant module.

  ## Example

  Defining a basic plugin that satisfies the minimum:

      defmodule MyPlugin do
        @behaviour Oban.Plugin

        use GenServer

        @impl Oban.Plugin
        def start_link(opts) do
          GenServer.start_link(__MODULE__, opts, name: opts[:name])
        end

        @impl GenServer
        def init(opts) do
          case validate(opts) do
            :ok -> {:ok, opts}
            {:error, reason} -> {:stop, reason}
          end
        end

        @impl Oban.Plugin
        def validate(opts) do
          if is_atom(opts[:mode])
            :ok
          else
            {:error, "expected opts to have a :mode key"}
          end
        end
      end
  """

  alias Oban.Config

  @type option :: {:conf, Config.t()} | {:name, GenServer.name()} | {atom(), term()}
  @type validator :: (option() -> :ok | {:error, term()})

  @doc """
  Starts a Plugin process linked to the current process.

  Plugins are typically started as part of an Oban supervision tree and will receive the current
  configuration as `:conf`, along with a `:name` and any other provided options.
  """
  @callback start_link([option()]) :: GenServer.on_start()

  @doc """
  Validate the structure, presence, or values of keyword options.
  """
  @callback validate([option()]) :: :ok | {:error, term()}

  @doc """
  A utility to help validate options without resorting to `throw` or `raise` for control flow.

  ## Example

  Ensure all keys are known and the correct type:

      validate(opts, fn
        {:conf, conf} when is_struct(conf) -> :ok
        {:name, name} when is_atom(name) -> :ok
        opt -> {:error, "unknown option: " <> inspect(opt)}
      end)
  """
  @spec validate([option()], validator()) :: :ok | {:error, term()}
  def validate(opts, validator) do
    Enum.reduce_while(opts, :ok, fn opt, acc ->
      case validator.(opt) do
        :ok -> {:cont, acc}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  @doc false
  @spec validate!([option()], ([option()] -> :ok | {:error, term()})) :: :ok
  def validate!(opts, validate) do
    with {:error, reason} <- validate.(opts), do: raise(ArgumentError, reason)
  end
end
