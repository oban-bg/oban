defmodule Oban.Job do
  @moduledoc false

  # TODO: Re-work these docs

  @doc """
  A Job is an Ecto schema used for asynchronous execution.

  ## Options

    * `:args` — a list of arguments passed to the worker during execution
    * `:queue` — a named queue to push the job into. Jobs may be pushed into any queue, regardless
      of whether jobs are currently being processed for the queue.
    * `:worker` — a module to execute the job in. The module must implement the `Oban.Worker`
      behaviour.

  ## Examples

  Push a job into the `:default` queue

      MyApp.Oban.push(args: [1, 2, 3], queue: :default, worker: MyApp.Worker)

  Generate a pre-configured job for `MyApp.Worker` and push it.

      [args: [1, 2, 3]] |> MyApp.Worker.new() |> MyApp.Oban.push()
  """

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
      |> coerce_field(:queue)
      |> coerce_field(:worker)

    %__MODULE__{}
    |> cast(params, @permitted)
    |> validate_required(@required)
    |> validate_number(:max_attempts, greater_than: 0, less_than: 50)
  end

  defp coerce_field(params, field) do
    case Map.get(params, field) do
      value when is_atom(value) and not is_nil(value) ->
        update_in(params, [field], &to_string/1)

      _ ->
        params
    end
  end
end
