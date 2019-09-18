defmodule Oban.Job do
  @moduledoc """
  A Job is an Ecto schema used for asynchronous execution.

  Job changesets are created by your application code and inserted into the database for
  asynchronous execution. Jobs can be inserted along with other application data as part of a
  transaction, which guarantees that jobs will only be triggered from a successful transaction.
  """
  @moduledoc since: "0.1.0"

  use Ecto.Schema

  import Ecto.Changeset

  @type args :: map()
  @type errors :: [%{at: DateTime.t(), attempt: pos_integer(), error: binary()}]

  @type unique_field :: [:args | :queue | :worker]

  @type unique_state :: [:available | :scheduled | :executing | :retryable | :completed]

  @type unique_option ::
          {:fields, [unique_field()]}
          | {:period, pos_integer()}
          | {:states, [unique_state()]}

  @type option ::
          {:args, args()}
          | {:max_attempts, pos_integer()}
          | {:queue, atom() | binary()}
          | {:schedule_in, pos_integer()}
          | {:scheduled_at, DateTime.t()}
          | {:unique, [unique_option()]}
          | {:worker, atom() | binary()}

  @type t :: %__MODULE__{
          id: pos_integer(),
          state: binary(),
          queue: binary(),
          worker: binary(),
          args: args(),
          errors: errors(),
          attempt: non_neg_integer(),
          attempted_by: [binary()],
          max_attempts: pos_integer(),
          inserted_at: DateTime.t(),
          scheduled_at: DateTime.t(),
          attempted_at: DateTime.t(),
          completed_at: DateTime.t(),
          unique: %{fields: [unique_field()], period: pos_integer(), states: [unique_state()]}
        }

  schema "oban_jobs" do
    field :state, :string, default: "available"
    field :queue, :string, default: "default"
    field :worker, :string
    field :args, :map
    field :errors, {:array, :map}, default: []
    field :attempt, :integer, default: 0
    field :attempted_by, {:array, :string}
    field :max_attempts, :integer, default: 20
    field :attempted_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec
    field :inserted_at, :utc_datetime_usec
    field :scheduled_at, :utc_datetime_usec
    field :unique, :map, virtual: true
  end

  @permitted ~w(
    args
    attempt
    attempted_by
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
    * `:schedule_in` - the number of seconds until the job should be executed
    * `:scheduled_at` - a time in the future after which the job should be executed
    * `:worker` — a module to execute the job in. The module must implement the `Oban.Worker`
      behaviour.
    * `:unique` — a keyword list of options specifying how uniquness will be calculated. The
      options define which fields will be used, for how long, and for which states.

  ## Examples

  Insert a job with the `:default` queue:

      %{id: 1, user_id: 2}
      |> Oban.Job.new(queue: :default, worker: MyApp.Worker)
      |> Oban.insert()

  Generate a pre-configured job for `MyApp.Worker` and push it:

      %{id: 1, user_id: 2} |> MyApp.Worker.new() |> Oban.insert()

  Schedule a job to run in 5 seconds:

      %{id: 1} |> MyApp.Worker.new(schedule_in: 5) |> Oban.insert()

  Insert a job, ensuring that it is unique within the past minute:

      %{id: 1} |> MyApp.Worker.new(unique: [period: 60]) |> Oban.insert()

  Insert a unique job based only on the worker field, and within multiple states:

      fields = [:worker]
      states = [:available, :scheduled, :executing, :retryable, :completed]

      %{id: 1}
      |> MyApp.Worker.new(unique: [fields: fields, period: 60, states: states])
      |> Oban.insert()
  """
  @spec new(args(), [option]) :: Ecto.Changeset.t()
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
    |> put_scheduling(params[:schedule_in])
    |> put_uniqueness(params[:unique])
    |> put_state()
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

  @unique_fields ~w(args queue worker)a
  @unique_period 60
  @unique_states ~w(available scheduled executing retryable completed)a

  @doc false
  @spec valid_unique_opt?({:fields | :period | :states, [atom()] | integer()}) :: boolean()
  def valid_unique_opt?({:fields, [_ | _] = fields}), do: fields -- @unique_fields == []
  def valid_unique_opt?({:period, period}), do: is_integer(period) and period > 0
  def valid_unique_opt?({:states, [_ | _] = states}), do: states -- @unique_states == []
  def valid_unique_opt?(_option), do: false

  defp put_scheduling(changeset, value) do
    case value do
      in_seconds when is_integer(in_seconds) ->
        scheduled_at = DateTime.add(DateTime.utc_now(), in_seconds)

        put_change(changeset, :scheduled_at, scheduled_at)

      nil ->
        changeset

      _ ->
        add_error(changeset, :schedule_in, "invalid value")
    end
  end

  defp put_state(changeset) do
    case fetch_change(changeset, :scheduled_at) do
      {:ok, _} -> put_change(changeset, :state, "scheduled")
      :error -> changeset
    end
  end

  defp put_uniqueness(changeset, value) do
    case value do
      [_ | _] = opts ->
        unique =
          opts
          |> Keyword.put_new(:fields, @unique_fields)
          |> Keyword.put_new(:period, @unique_period)
          |> Keyword.put_new(:states, @unique_states)
          |> Map.new()

        case validate_unique_opts(unique) do
          :ok ->
            put_change(changeset, :unique, unique)

          {:error, field, value} ->
            add_error(changeset, :unique, "invalid unique option for #{field}, #{inspect(value)}")
        end

      nil ->
        changeset

      _ ->
        add_error(changeset, :unique, "invalid unique options")
    end
  end

  defp validate_unique_opts(unique) do
    Enum.reduce_while(unique, :ok, fn {key, val}, _acc ->
      if valid_unique_opt?({key, val}) do
        {:cont, :ok}
      else
        {:halt, {:error, key, val}}
      end
    end)
  end

  defp to_clean_string(value) do
    value
    |> to_string()
    |> String.trim_leading("Elixir.")
  end
end
