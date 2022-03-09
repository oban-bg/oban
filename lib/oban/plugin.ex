defmodule Oban.Plugin do
  @moduledoc """
  Defines a shared behaviour for Oban plugins.

  In addition to implementing the Plugin behaviour, all plugins **must** be a `GenServer`, `Agent`, or
  another OTP compliant module.

  ## Example

  Defining a basic plugin that satisfies the minimum behaviour:

      defmodule MyPlugin do
        @behaviour Oban.Plugin

        use GenServer

        @impl Oban.Plugin
        def start_link(opts) do
          GenServer.start_link(__MODULE__, opts, name: opts[:name])
        end

        @impl Oban.Plugin
        def validate(opts) do
          if is_atom(opts[:mode])
            :ok
          else
            {:error, "expected opts to have a :mode key"}
          end
        end

        @impl GenServer
        def init(opts) do
          case validate(opts) do
            :ok -> {:ok, opts}
            {:error, reason} -> {:stop, reason}
          end
        end
      end
  """

  alias Oban.Config

  @type option :: {:conf, Config.t()} | {:name, GenServer.name()} | {atom(), term()}

  @doc """
  Starts a Plugin process linked to the current process.

  Plugins are typically started as part of an Oban supervision tree and will receive the current
  configuration as `:conf`, along with a `:name` and any other provided options.
  """
  @callback start_link([option()]) :: GenServer.on_start()

  @doc """
  Validate the structure, presence, or values of keyword options.
  """
  @callback validate([option()]) :: :ok | {:error, String.t()}
end
