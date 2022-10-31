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
  @type tags :: [binary()]

  @type unique_field :: [:args | :meta | :queue | :worker]

  @type unique_period :: pos_integer() | :infinity

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

  @type schedule_in_option ::
          pos_integer()
          | {pos_integer(),
             :second
             | :seconds
             | :minute
             | :minutes
             | :hour
             | :hours
             | :day
             | :days
             | :week
             | :weeks}

  @type option ::
          {:args, args()}
          | {:max_attempts, pos_integer()}
          | {:meta, map()}
          | {:priority, pos_integer()}
          | {:queue, atom() | binary()}
          | {:schedule_in, schedule_in_option()}
          | {:replace_args, boolean()}
          | {:replace, [replace_option()]}
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
          attempted_by: [binary()],
          max_attempts: pos_integer(),
          meta: map(),
          priority: pos_integer(),
          inserted_at: DateTime.t(),
          scheduled_at: DateTime.t(),
          attempted_at: DateTime.t(),
          completed_at: DateTime.t(),
          discarded_at: DateTime.t(),
          cancelled_at: DateTime.t(),
          conf: Oban.Config.t(),
          conflict?: boolean(),
          replace: [replace_option()],
          unique: %{fields: [unique_field()], period: unique_period(), states: [unique_state()]},
          unsaved_error: %{kind: atom(), reason: term(), stacktrace: Exception.stacktrace()}
        }

  @type changeset :: Ecto.Changeset.t(t())
  @type changeset_fun :: (map() -> changeset())
  @type changeset_list :: [changeset()]
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
    field :priority, :integer, default: 0

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

  @virtual_params ~w(replace replace_args schedule_in unique)a

  @required_params ~w(worker args)a

  @replace_options ~w(args max_attempts meta priority queue scheduled_at tags worker)a

  @doc """
  Construct a new job changeset ready for insertion into the database.

  ## Options

    * `:max_attempts` — the maximum number of times a job can be retried if there are errors
      during execution
    * `:meta` — a map containing additional information about the job
    * `:priority` — a numerical indicator from 0 to 3 of how important this job is relative to
      other jobs in the same queue. The lower the number, the higher priority the job.
    * `:queue` — a named queue to push the job into. Jobs may be pushed into any queue, regardless
      of whether jobs are currently being processed for the queue.
    * `:replace` - a list of keys to replace on a unique conflict
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

  Generate a pre-configured job for `MyApp.Worker` and push it:

      %{id: 1, user_id: 2} |> MyApp.Worker.new() |> Oban.insert()

  Schedule a job to run in 5 seconds:

      %{id: 1} |> MyApp.Worker.new(schedule_in: 5) |> Oban.insert()

  Schedule a job to run in 5 minutes:

      %{id: 1} |> MyApp.Worker.new(schedule_in: {5, :minutes}) |> Oban.insert()

  Insert a job, ensuring that it is unique within the past minute:

      %{id: 1} |> MyApp.Worker.new(unique: [period: 60]) |> Oban.insert()

  Insert a unique job based only on the worker field, and within multiple states:

      fields = [:worker]
      states = [:available, :scheduled, :executing, :retryable, :completed]

      %{id: 1}
      |> MyApp.Worker.new(unique: [fields: fields, period: 60, states: states])
      |> Oban.insert()

  Insert a unique job considering only the worker and specified keys in the args:

      keys = [:account_id, :url]

      %{account_id: 1, url: "https://example.com"}
      |> MyApp.Worker.new(unique: [fields: [:args, :worker], keys: keys])
      |> Oban.insert()

  Insert a unique job considering only specified keys in the meta:

      unique = [fields: [:meta], keys: [:slug]]

      %{id: 1}
      |> MyApp.Worker.new(meta: %{slug: "unique-key"}, unique: unique)
      |> Oban.insert()
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
    |> put_scheduling(params[:schedule_in])
    |> put_uniqueness(params[:unique])
    |> put_replace(params[:replace], params[:replace_args])
    |> validate_subset(:replace, @replace_options)
    |> put_state()
    |> validate_length(:queue, min: 1, max: 128)
    |> validate_length(:worker, min: 1, max: 128)
    |> validate_number(:max_attempts, greater_than: 0)
    |> validate_number(:priority, greater_than: -1, less_than: 4)
    |> check_constraint(:attempt, name: :attempt_range)
    |> check_constraint(:max_attempts, name: :positive_max_attempts)
    |> check_constraint(:priority, name: :priority_range)
  end

  @unique_fields ~w(args queue worker)a
  @unique_period 60
  @unique_states ~w(scheduled available executing retryable completed)a

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
  def states, do: @unique_states ++ [:discarded, :cancelled]

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
    |> Ecto.Changeset.apply_changes()
    |> Map.from_struct()
    |> Enum.reduce(%{}, fn {key, val}, acc ->
      if key in @permitted_params and not is_nil(val) do
        Map.put(acc, key, val)
      else
        acc
      end
    end)
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
  @spec valid_unique_opt?({:fields | :period | :states, [atom()] | integer()}) :: boolean()
  def valid_unique_opt?({:fields, [_ | _] = fields}), do: fields -- [:meta | @unique_fields] == []
  def valid_unique_opt?({:keys, []}), do: true
  def valid_unique_opt?({:keys, [_ | _] = keys}), do: Enum.all?(keys, &is_atom/1)
  def valid_unique_opt?({:period, :infinity}), do: true
  def valid_unique_opt?({:period, period}), do: is_integer(period) and period > 0
  def valid_unique_opt?({:states, [_ | _] = states}), do: states -- states() == []
  def valid_unique_opt?(_option), do: false

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

  defguardp is_timestampable(value)
            when is_integer(value) or
                   (is_integer(elem(value, 0)) and elem(value, 1) in @time_units)

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
          |> Map.new()
          |> Map.put_new(:fields, @unique_fields)
          |> Map.put_new(:keys, [])
          |> Map.put_new(:period, @unique_period)
          |> Map.put_new(:states, @unique_states)

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

  defp put_replace(changeset, replace, replace_args) do
    case {replace, replace_args} do
      {nil, true} ->
        put_change(changeset, :replace, [:args])

      {[_ | _], true} ->
        put_change(changeset, :replace, [:args | replace])

      {[_ | _], nil} ->
        put_change(changeset, :replace, replace)

      _ ->
        changeset
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

  def validate_keys(changeset, params, keys) do
    keys = Enum.map(keys, &to_string/1)

    Enum.reduce(params, changeset, fn {key, _val}, acc ->
      if to_string(key) in keys do
        acc
      else
        add_error(acc, :base, "unknown option #{inspect(key)} provided")
      end
    end)
  end

  defp to_timestamp(seconds) when is_integer(seconds) do
    DateTime.add(DateTime.utc_now(), seconds, :second)
  end

  defp to_timestamp({seconds, :second}), do: to_timestamp(seconds)
  defp to_timestamp({seconds, :seconds}), do: to_timestamp(seconds)
  defp to_timestamp({minutes, :minute}), do: to_timestamp(minutes * 60)
  defp to_timestamp({minutes, :minutes}), do: to_timestamp({minutes, :minute})
  defp to_timestamp({hours, :hour}), do: to_timestamp(hours * 60 * 60)
  defp to_timestamp({hours, :hours}), do: to_timestamp({hours, :hour})
  defp to_timestamp({days, :day}), do: to_timestamp(days * 24 * 60 * 60)
  defp to_timestamp({days, :days}), do: to_timestamp({days, :day})
  defp to_timestamp({weeks, :week}), do: to_timestamp(weeks * 7 * 24 * 60 * 60)
  defp to_timestamp({weeks, :weeks}), do: to_timestamp({weeks, :week})

  defp validate_unique_opts(unique) do
    Enum.reduce_while(unique, :ok, fn {key, val}, _acc ->
      if valid_unique_opt?({key, val}) do
        {:cont, :ok}
      else
        {:halt, {:error, key, val}}
      end
    end)
  end
end
