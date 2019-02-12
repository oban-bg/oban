defmodule Oban.Job do
  @moduledoc """
  A Job is an Ecto schema used for asynchronous execution.

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

      %{id: 1} |> MyApp.Worker.new(schedule_in: 5) |> MyApp.Repo.insert()
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
      |> coerce_scheduling()

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

  defp coerce_scheduling(%{scheduled_in: in_seconds} = params) when is_integer(in_seconds) do
    scheduled_at = NaiveDateTime.add(NaiveDateTime.utc_now(), in_seconds)

    params
    |> Map.delete(:in)
    |> Map.put(:scheduled_at, scheduled_at)
  end

  defp coerce_scheduling(params), do: params
end
