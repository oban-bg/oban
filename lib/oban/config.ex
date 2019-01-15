defmodule Oban.Config do
  @moduledoc false

  @type t :: %__MODULE__{}

  defstruct [:database, :database_name, :group, :ident, :maxlen, :otp_app, streams: []]

  @spec new(Keyword.t()) :: t()
  def new(opts) when is_list(opts) do
    struct!(__MODULE__, opts)
  end

  @doc false
  @spec child_spec(t()) :: Supervisor.child_spec()
  def child_spec(config) do
    %{id: __MODULE__, start: {Agent, :start_link, [config]}}
  end

  @doc """
  Get the configuration for a given pid.

  Each oban supervision tree stores a configuration instance.
  """
  @spec get(server :: pid()) :: t()
  def get(server) when is_pid(server) do
    Agent.get(server, &(&1))
  end
end
