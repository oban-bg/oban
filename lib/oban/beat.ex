defmodule Oban.Beat do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{
          node: binary(),
          queue: binary(),
          limit: pos_integer(),
          paused: boolean(),
          running: list(pos_integer()),
          inserted_at: DateTime.t(),
          started_at: DateTime.t()
        }

  @primary_key false
  schema "oban_beats" do
    field :node, :string
    field :queue, :string
    field :nonce, :string
    field :limit, :integer
    field :paused, :boolean, default: false
    field :running, {:array, :integer}, default: []
    field :inserted_at, :utc_datetime_usec
    field :started_at, :utc_datetime_usec
  end

  @permitted ~w(node queue nonce limit paused running inserted_at started_at)a
  @required ~w(node queue nonce limit paused running started_at)a

  @spec new(map()) :: Ecto.Changeset.t()
  def new(params) when is_map(params) do
    %__MODULE__{}
    |> cast(params, @permitted)
    |> validate_required(@required)
    |> validate_length(:node, min: 1, max: 128)
    |> validate_length(:nonce, min: 1, max: 16)
    |> validate_length(:queue, min: 1, max: 128)
    |> validate_number(:limit, greater_than: 0)
  end
end
