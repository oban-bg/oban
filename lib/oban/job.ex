defmodule Oban.Job do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{
    id: pos_integer(),
    state: binary(),
    queue: binary(),
    worker: binary(),
    args: map(),
    attempt: non_neg_integer(),
    max_attempts: non_neg_integer(),
    inserted_at: DateTime.t(),
    scheduled_at: DateTime.t(),
    attempted_at: DateTime.t()
  }

  schema "oban_jobs" do
    field :state, :string, default: "available"
    field :queue, :string, default: "default"
    field :worker, :string
    field :args, :map
    field :attempt, :integer, default: 0
    field :max_attempts, :integer, default: 20
    field :inserted_at, :utc_datetime_usec
    field :scheduled_at, :utc_datetime_usec
    field :attempted_at, :utc_datetime_usec
  end

  @permitted ~w(queue worker args max_attempts scheduled_at)a
  @required ~w(worker args)a

  @spec new(args :: map(), opts :: Keyword.t()) :: Ecto.Changeset.t()
  def new(args, opts \\ []) when is_map(args) and is_list(opts) do
    params =
      opts
      |> Keyword.put(:args, args)
      |> Map.new()

    %__MODULE__{}
    |> cast(params, @permitted)
    |> validate_required(@required)
    |> validate_number(:max_attempts, greater_than: 0, less_than: 50)
  end
end
