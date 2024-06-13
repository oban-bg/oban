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

  alias Ecto.Changeset
  alias Oban.Validation

  @type args :: map()
  @type errors :: [%{at: DateTime.t(), attempt: pos_integer(), error: binary()}]
  @type tags :: [binary()]

  @type time_unit ::
          :second
          | :seconds
          | :minute
          | :minutes
          | :hour
          | :hours
          | :day
          | :days
          | :week
          | :weeks

  @type unique_field :: :args | :meta | :queue | :worker

  @type unique_period :: pos_integer() | {pos_integer(), time_unit()} | :infinity

  @type unique_state :: [
          :available
          | :cancelled
          | :completed
          | :discarded
          | :executing
          | :retryable
          | :scheduled
        ]

  @type unique_option ::
          {:fields, [unique_field()]}
          | {:keys, [atom()]}
          | {:period, unique_period()}
          | {:states, [unique_state()]}
          | {:timestamp, :inserted_at | :scheduled_at}

  @type replace_option :: [
          :args
          | :max_attempts
          | :meta
          | :priority
          | :queue
          | :scheduled_at
          | :tags
          | :worker
        ]

  @type replace_by_state_option ::
          {:available, [replace_option()]}
          | {:cancelled, [replace_option()]}
          | {:completed, [replace_option()]}
          | {:discarded, [replace_option()]}
          | {:executing, [replace_option()]}
          | {:retryable, [replace_option()]}
          | {:scheduled, [replace_option()]}

  @type schedule_in_option :: pos_integer() | {pos_integer(), time_unit()}

  @type option ::
          {:args, args()}
          | {:max_attempts, pos_integer()}
          | {:meta, map()}
          | {:priority, 0..9}
          | {:queue, atom() | binary()}
          | {:replace, [replace_option() | replace_by_state_option()]}
          | {:replace_args, boolean()}
          | {:schedule_in, schedule_in_option()}
          | {:scheduled_at, DateTime.t()}
          | {:tags, tags()}
          | {:unique, [unique_option()]}
          | {:worker, atom() | binary()}

  @type t :: %__MODULE__{
          id: pos_integer(),
          state: binary(),
          queue: binary(),
          worker: binary(),
          args: args(),
          errors: errors(),
          tags: tags(),
          attempt: non_neg_integer(),
          attempted_by: [binary()] | nil,
          max_attempts: pos_integer(),
          meta: map(),
          priority: 0..9,
          inserted_at: DateTime.t(),
          scheduled_at: DateTime.t(),
          attempted_at: DateTime.t() | nil,
          completed_at: DateTime.t() | nil,
          discarded_at: DateTime.t() | nil,
          cancelled_at: DateTime.t() | nil,
          conf: Oban.Config.t() | nil,
          conflict?: boolean(),
          replace: [replace_option() | replace_by_state_option()] | nil,
          unique:
            %{fields: [unique_field()], period: unique_period(), states: [unique_state()]} | nil,
          unsaved_error:
            %{
              kind: Exception.kind(),
              reason: term(),
              stacktrace: Exception.stacktrace()
            }
            | nil
        }

  @type changeset :: Ecto.Changeset.t(t())
  @type changeset_fun :: (map() -> changeset())
  @type changeset_list :: Enumerable.t(changeset())
  @type changeset_list_fun :: (map() -> changeset_list())

  schema "oban_jobs" do
    field :state, :string, default: "available"
    field :queue, :string, default: "default"
    field :worker, :string
    field :args, :map
    field :meta, :map, default: %{}
    field :tags, {:array, :string}, default: []
    field :errors, {:array, :map}, default: []
    field :attempt, :integer, default: 0
    field :attempted_by, {:array, :string}
    field :max_attempts, :integer, default: 20
    field :priority, :integer

    field :attempted_at, :utc_datetime_usec
    field :cancelled_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec
    field :discarded_at, :utc_datetime_usec
    field :inserted_at, :utc_datetime_usec
    field :scheduled_at, :utc_datetime_usec

    field :conf, :map, virtual: true
    field :conflict?, :boolean, virtual: true, default: false
    field :replace, {:array, :any}, virtual: true
    field :unique, :map, virtual: true
    field :unsaved_error, :map, virtual: true
  end

  @permitted_params ~w(
    args
    attempt
    attempted_by
    attempted_at
    completed_at
    discarded_at
    cancelled_at
    errors
    inserted_at
    max_attempts
    meta
    priority
    queue
    scheduled_at
    state
    tags
    worker
  )a

  @required_params ~w(worker args)a
  @replace_options ~w(args max_attempts meta priority queue scheduled_at tags worker)a
  @virtual_params ~w(replace replace_args schedule_in unique)a

  @time_units ~w(
    second
    seconds
    minute
    minutes
    hour
    hours
    day
    days
    week
    weeks
  )a

  @unique_fields ~w(args meta queue worker)a
  @unique_timestamps ~w(inserted_at scheduled_at)a

  defguardp is_timestampable(value)
            when is_integer(value) or
                   (is_integer(elem(value, 0)) and elem(value, 1) in @time_units)

  @doc """
  Construct a new job changeset ready for insertion into the database.

  ## Options

    * `:max_attempts` — the maximum number of times a job can be retried if there are errors
      during execution

    * `:meta` — a map containing additional information about the job

    * `:priority` — a numerical indicator from 0 to 9 of how important this job is relative to
      other jobs in the same queue. The lower the number, the higher priority the job.

    * `:queue` — a named queue to push the job into. Jobs may be pushed into any queue, regardless
      of whether jobs are currently being processed for the queue.

    * `:replace` - a list of keys to replace per state on a unique conflict

    * `:scheduled_at` - a time in the future after which the job should be executed

    * `:schedule_in` - the number of seconds until the job should be executed or a tuple containing
      a number and unit

    * `:tags` — a list of tags to group and organize related jobs, i.e. to identify scheduled jobs

    * `:unique` — a keyword list of options specifying how uniqueness will be calculated. The
      options define which fields will be used, for how long, with which keys, and for which states.

    * `:worker` — a module to execute the job in. The module must implement the `Oban.Worker`
      behaviour.

  ## Examples

  Insert a job with the `:default` queue:

      %{id: 1, user_id: 2}
      |> Oban.Job.new(queue: :default, worker: MyApp.Worker)
      |> Oban.insert()

  Generate a pre-configured job for `MyApp.Worker`:

      MyApp.Worker.new(%{id: 1, user_id: 2})

  Schedule a job to run in 5 seconds:

      MyApp.Worker.new(%{id: 1}, schedule_in: 5)

  Schedule a job to run in 5 minutes:

      MyApp.Worker.new(%{id: 1}, schedule_in: {5, :minutes})

  Insert a job, ensuring that it is unique within the past minute:

      MyApp.Worker.new(%{id: 1}, unique: [period: {1, :minute}])

  Insert a unique job where the period is compared to the `scheduled_at` timestamp rather than
  `inserted_at`:

      MyApp.Worker.new(%{id: 1}, unique: [period: 60, timestamp: :scheduled_at])

  Insert a unique job based only on the worker field, and within multiple states:

      fields = [:worker]
      states = [:available, :scheduled, :executing, :retryable, :completed]

      MyApp.Worker.new(%{id: 1}, unique: [fields: fields, period: 60, states: states])

  Insert a unique job considering only the worker and specified keys in the args:

      keys = [:account_id, :url]
      args = %{account_id: 1, url: "https://example.com"}

      MyApp.Worker.new(args, unique: [fields: [:args, :worker], keys: keys])

  Insert a unique job considering only specified keys in the meta:

      unique = [fields: [:meta], keys: [:slug]]

      MyApp.Worker.new(%{id: 1}, meta: %{slug: "unique-key"}, unique: unique)
  """
  @doc since: "0.1.0"
  @spec new(args(), [option()]) :: changeset()
  def new(args, opts \\ []) when is_map(args) and is_list(opts) do
    params =
      opts
      |> Keyword.put(:args, args)
      |> Map.new()
      |> coerce_field(:queue, &to_string/1)
      |> coerce_field(:worker, &Oban.Worker.to_string/1)
      |> normalize_tags()

    %__MODULE__{}
    |> cast(params, @permitted_params)
    |> validate_keys(params, @permitted_params ++ @virtual_params)
    |> validate_required(@required_params)
    |> put_replace(params[:replace], params[:replace_args])
    |> put_scheduling(params[:schedule_in])
    |> put_state()
    |> put_unique(params[:unique])
    |> validate_length(:queue, min: 1, max: 128)
    |> validate_length(:worker, min: 1, max: 128)
    |> validate_number(:max_attempts, greater_than: 0)
    |> validate_number(:priority, greater_than: -1, less_than: 10)
    |> validate_replace()
    |> validate_unique()
    |> check_constraint(:attempt, name: :attempt_range)
    |> check_constraint(:max_attempts, name: :positive_max_attempts)
    |> check_constraint(:priority, name: :priority_range)
  end

  @doc """
  A canonical list of all possible job states.

  This may be used to build up `:unique` options without duplicating states in application code.

  ## Examples

      iex> Oban.Job.states() -- [:completed, :discarded]
      [:scheduled, :available, :executing, :retryable, :cancelled]

  ## Job State Transitions

  * `:scheduled`—Jobs inserted with `scheduled_at` in the future are `:scheduled`. After the
    `scheduled_at` time has ellapsed the `Oban.Plugins.Stager` will transition them to `:available`

  * `:available`—Jobs without a future `scheduled_at` timestamp are inserted as `:available` and may
    execute immediately

  * `:executing`—Available jobs may be ran, at which point they are `:executing`

  * `:retryable`—Jobs that fail and haven't exceeded their max attempts are transitiond to
    `:retryable` and rescheduled until after a backoff period. Once the backoff has ellapsed the
    `Oban.Plugins.Stager` will transition them back to `:available`

  * `:completed`—Jobs that finish executing succesfully are marked `:completed`

  * `:discarded`—Jobs that fail and exhaust their max attempts, or return a `:discard` tuple during
    execution, are marked `:discarded`

  * `:cancelled`—Jobs that are cancelled intentionally

  """
  @doc since: "2.1.0"
  def states do
    ~w(scheduled available executing retryable completed discarded cancelled)a
  end

  @doc """
  Convert a Job changeset into a map suitable for database insertion.

  ## Examples

  Convert a worker generated changeset into a plain map:

      %{id: 123}
      |> MyApp.Worker.new()
      |> Oban.Job.to_map()
  """
  @doc since: "0.9.0"
  @spec to_map(Ecto.Changeset.t(t())) :: map()
  def to_map(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.apply_action!(:insert)
    |> Map.from_struct()
    |> Enum.reduce(%{}, fn {key, val}, acc ->
      if key in @permitted_params and not is_nil(val) do
        Map.put(acc, key, val)
      else
        acc
      end
    end)
  end

  @doc """
  Normalize, blame, and format a job's `unsaved_error` into the stored error format.

  Formatted errors are stored in a job's `errors` field.
  """
  @doc since: "2.14.0"
  def format_attempt(%__MODULE__{attempt: attempt, unsaved_error: unsaved}) do
    %{kind: kind, reason: error, stacktrace: stacktrace} = unsaved

    {blamed, stacktrace} = Exception.blame(kind, error, stacktrace)

    error = Exception.format(kind, blamed, stacktrace)

    %{attempt: attempt, at: DateTime.utc_now(), error: error}
  end

  defp coerce_field(params, field, fun) do
    case Map.get(params, field) do
      value when is_atom(value) and not is_nil(value) ->
        update_in(params, [field], fun)

      value when is_binary(value) ->
        update_in(params, [field], fun)

      _ ->
        params
    end
  end

  @doc false
  @spec cast_period(unique_period()) :: pos_integer()
  def cast_period({value, unit}) do
    unit = to_string(unit)

    cond do
      unit in ~w(second seconds) -> value
      unit in ~w(minute minutes) -> value * 60
      unit in ~w(hour hours) -> value * 60 * 60
      unit in ~w(day days) -> value * 24 * 60 * 60
      unit in ~w(week weeks) -> value * 24 * 60 * 60 * 7
      true -> unit
    end
  end

  def cast_period(period), do: period

  defp put_replace(changeset, replace, replace_args) do
    with_states = fn fields ->
      for state <- states(), do: {state, fields}
    end

    case {replace, replace_args} do
      {nil, true} ->
        put_change(changeset, :replace, with_states.([:args]))

      {[field | _] = replace, true} when is_atom(field) ->
        put_change(changeset, :replace, with_states.([:args | replace]))

      {[field | _] = replace, _} when is_atom(field) ->
        put_change(changeset, :replace, with_states.(replace))

      {replace, _} when is_list(replace) ->
        put_change(changeset, :replace, replace)

      _ ->
        changeset
    end
  end

  defp put_scheduling(changeset, value) do
    case value do
      value when is_timestampable(value) ->
        scheduled_at = to_timestamp(value)

        put_change(changeset, :scheduled_at, scheduled_at)

      nil ->
        changeset

      _ ->
        add_error(changeset, :schedule_in, "invalid value")
    end
  end

  defp put_state(changeset) do
    case {get_change(changeset, :state), get_change(changeset, :scheduled_at)} do
      {nil, %_{}} -> put_change(changeset, :state, "scheduled")
      _ -> changeset
    end
  end

  defp put_unique(changeset, value) do
    case value do
      [_ | _] = opts ->
        unique =
          opts
          |> Map.new()
          |> Map.put_new(:fields, ~w(args queue worker)a)
          |> Map.put_new(:keys, [])
          |> Map.put_new(:states, ~w(scheduled available executing retryable completed)a)
          |> Map.put_new(:timestamp, :inserted_at)
          |> Map.update(:period, 60, &cast_period/1)

        put_change(changeset, :unique, unique)

      nil ->
        changeset

      _ ->
        add_error(changeset, :unique, "invalid unique options")
    end
  end

  defp normalize_tags(%{tags: [_ | _] = tags} = params) do
    normalize = fn string ->
      string
      |> to_string()
      |> String.trim()
      |> String.downcase()
    end

    tags =
      tags
      |> Enum.map(normalize)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    %{params | tags: tags}
  end

  defp normalize_tags(params), do: params

  defp to_timestamp(seconds) when is_integer(seconds) do
    DateTime.add(DateTime.utc_now(), seconds, :second)
  end

  defp to_timestamp({period, unit}) do
    {period, unit}
    |> cast_period()
    |> to_timestamp()
  end

  # Validation

  defp validate_keys(changeset, params, keys) do
    keys = Enum.map(keys, &to_string/1)

    Enum.reduce(params, changeset, fn {key, _val}, acc ->
      if to_string(key) in keys do
        acc
      else
        add_error(acc, :base, "unknown option #{inspect(key)} provided")
      end
    end)
  end

  @doc false
  def validate_replace(%Changeset{} = changeset) do
    replace = get_change(changeset, :replace)

    if is_list(replace) do
      case validate_replace(replace) do
        :ok ->
          changeset

        {:error, error} ->
          add_error(changeset, :replace, "invalid replace option, #{inspect(error)}")
      end
    else
      changeset
    end
  end

  def validate_replace(replace) do
    unknown_state =
      replace
      |> Keyword.keys()
      |> Enum.find(&(&1 not in states()))

    unknown_field =
      replace
      |> Keyword.values()
      |> List.flatten()
      |> Enum.find(&(&1 not in @replace_options))

    cond do
      not is_nil(unknown_state) ->
        {:error, "has an invalid state: #{inspect(unknown_state)}"}

      not is_nil(unknown_field) ->
        {:error, "has an invalid field: #{inspect(unknown_field)}"}

      true ->
        :ok
    end
  end

  @doc false
  def validate_unique(%Changeset{} = changeset) do
    unique = get_change(changeset, :unique)

    if is_map(unique) do
      case validate_unique(Map.to_list(unique)) do
        :ok ->
          changeset

        {:error, error} ->
          add_error(changeset, :unique, "invalid unique option, #{inspect(error)}")
      end
    else
      changeset
    end
  end

  def validate_unique(unique) do
    Validation.validate(:unique, unique, fn
      {:fields, [_ | _] = fields} ->
        unless Enum.all?(fields, &(&1 in @unique_fields)) do
          {:error, "expected :fields #{inspect(fields)} to overlap #{inspect(@unique_fields)}"}
        end

      {:keys, keys} ->
        unless is_list(keys) and Enum.all?(keys, &is_atom/1) do
          {:error, "expected :keys to be a list of atoms"}
        end

      {:period, :infinity} ->
        :ok

      {:period, {period, unit}} ->
        unless is_integer(period) and period > 0 and unit in @time_units do
          {:error, "expected :period to be positive and unit to be in #{inspect(@time_units)}"}
        end

      {:period, period} ->
        unless is_integer(period) and period > 0 do
          {:error, "expected :period to be a positive integer"}
        end

      {:states, [_ | _] = states} ->
        unless Enum.all?(states, &(&1 in states())) do
          {:error, "expected :states #{inspect(states)} to overlap in #{inspect(states())}"}
        end

      {:timestamp, timestamp} ->
        unless timestamp in @unique_timestamps do
          {:error, "expected :timestamp to be one of #{inspect(@unique_timestamps)}"}
        end

      option ->
        {:error, "unknown option, #{inspect(option)}"}
    end)
  end
end
