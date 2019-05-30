defmodule Oban.Job do
  @moduledoc """
  A Job is an Ecto schema used for asynchronous execution.

  Job changesets are created by your application code and inserted into the database for
  asynchronous execution. Jobs can be inserted along with other application data as part of a
  transaction, which guarantees that jobs will only be triggered from a successful transaction.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type args :: map()
  @type errors :: [%{at: DateTime.t(), attempt: pos_integer(), error: binary()}]
  @type option ::
          {:queue, atom() | binary()}
          | {:worker, atom() | binary()}
          | {:args, args()}
          | {:max_attempts, pos_integer()}
          | {:scheduled_at, DateTime.t()}
          | {:scheduled_in, pos_integer()}

  @type t :: %__MODULE__{
          id: pos_integer(),
          state: binary(),
          queue: binary(),
          worker: binary(),
          args: args(),
          errors: errors(),
          attempt: non_neg_integer(),
          max_attempts: pos_integer(),
          inserted_at: DateTime.t(),
          scheduled_at: DateTime.t(),
          attempted_at: DateTime.t(),
          completed_at: DateTime.t()
        }

  schema "oban_jobs" do
    field :state, :string, default: "available"
    field :queue, :string, default: "default"
    field :worker, :string
    field :args, :map
    field :errors, {:array, :map}, default: []
    field :attempt, :integer, default: 0
    field :max_attempts, :integer, default: 20
    field :attempted_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec
    field :inserted_at, :utc_datetime_usec
    field :scheduled_at, :utc_datetime_usec
  end

  @permitted ~w(
    args
    attempt
    attempted_at
    completed_at
    errors
    inserted_at
    max_attempts
    queue
    scheduled_at
    state
    worker
  )a

  @required ~w(worker args)a

  @doc """
  Construct a new job changeset ready for insertion into the database.

  ## Options

    * `:max_attempts` — the maximum number of times a job can be retried if there are errors during execution
    * `:queue` — a named queue to push the job into. Jobs may be pushed into any queue, regardless
      of whether jobs are currently being processed for the queue.
    * `:scheduled_in` - the number of seconds until the job should be executed
    * `:scheduled_at` - a time in the future after which the job should be executed
    * `:worker` — a module to execute the job in. The module must implement the `Oban.Worker`
      behaviour.

  ## Examples

  Insert a job with the `:default` queue:

      %{id: 1, user_id: 2}
      |> Oban.Job.new(queue: :default, worker: MyApp.Worker)
      |> MyApp.Repo.insert()

  Generate a pre-configured job for `MyApp.Worker` and push it:

      %{id: 1, user_id: 2} |> MyApp.Worker.new() |> MyApp.Repo.insert()

  Schedule a job to run in 5 seconds:

      %{id: 1} |> MyApp.Worker.new(scheduled_in: 5) |> MyApp.Repo.insert()
  """
  @spec new(args(), [option]) :: Ecto.Changeset.t()
  def new(args, opts \\ []) when is_map(args) and is_list(opts) do
    params =
      opts
      |> Keyword.put(:args, args)
      |> Map.new()
      |> coerce_field(:queue)
      |> coerce_field(:worker)
      |> coerce_scheduling()

    %__MODULE__{}
    |> cast(params, @permitted)
    |> validate_required(@required)
    |> validate_length(:queue, min: 1, max: 128)
    |> validate_length(:worker, min: 1, max: 128)
    |> validate_number(:max_attempts, greater_than: 0, less_than: 50)
  end

  @doc false
  def coerce_field(params, field) do
    case Map.get(params, field) do
      value when is_atom(value) and not is_nil(value) ->
        update_in(params, [field], &to_clean_string/1)

      value when is_binary(value) ->
        update_in(params, [field], &to_clean_string/1)

      _ ->
        params
    end
  end

  defp coerce_scheduling(%{scheduled_in: in_seconds} = params) when is_integer(in_seconds) do
    scheduled_at = NaiveDateTime.add(NaiveDateTime.utc_now(), in_seconds)

    params
    |> Map.delete(:in)
    |> Map.put(:scheduled_at, scheduled_at)
    |> Map.put(:state, "scheduled")
  end

  defp coerce_scheduling(params), do: params

  defp to_clean_string(value) do
    value
    |> to_string()
    |> String.trim_leading("Elixir.")
  end
end
