defmodule Oban.Worker do
  @moduledoc """
  Defines a behavior and macro to guide the creation of worker modules.

  Worker modules do the work of processing a job. At a minimum they must define a `perform/2`
  function, which will be called with an `args` map and the job struct.

  ## Defining Workers

  Define a worker to process jobs in the `events` queue, retrying at most 10 times if a job fails,
  and ensuring that duplicate jobs aren't enqueued within a 30 second period:

      defmodule MyApp.Workers.Business do
        use Oban.Worker, queue: "events", max_attempts: 10, unique: [period: 30]

        @impl Worker
        def perform(_args, %Oban.Job{attempt: attempt}) when attempt > 3 do
          IO.inspect(attempt)
        end

        def perform(args, _job) do
          IO.inspect(args)
        end
      end

  The `perform/2` function receives an args map and an `Oban.Job` struct as arguments.  This
  allows workers to change the behavior of `perform/2` based on attributes of the Job, e.g. the
  number of attempts or when it was inserted.

  A job is considered complete if `perform/2` returns a non-error value, and it doesn't raise an
  exception or have an unhandled exit.

  Any of these return values or error events will fail the job:

  * return `{:error, error}`
  * return `:error`
  * an unhandled exception
  * an unhandled exit or throw

  As an example of error tuple handling, this worker may return an error tuple when the value is
  less than one:

      defmodule MyApp.Workers.ErrorExample do
        use Oban.Worker

        @impl Worker
        def perform(%{"value" => value}, _job) do
          if value > 1 do
            :ok
          else
            {:error, "invalid value given: " <> inspect(value)}
          end
        end
      end

  ## Enqueuing Jobs

  All workers implement a `new/2` function that converts an args map into a job changeset
  suitable for inserting into the database for later execution:

      %{in_the: "business", of_doing: "business"}
      |> MyApp.Workers.Business.new()
      |> Oban.insert()

  The worker's defaults may be overridden by passing options:

      %{vote_for: "none of the above"}
      |> MyApp.Workers.Business.new(queue: "special", max_attempts: 5)
      |> Oban.insert()

  Uniqueness options may also be overridden by passing options:

      %{expensive: "business"}
      |> MyApp.Workers.Business.new(unique: [period: 120, fields: [:worker]])
      |> Oban.insert()

  Note that `unique` options aren't merged, they are overridden entirely.

  See `Oban.Job` for all available options.

  ## Unique Jobs

  The unique jobs feature lets you specify constraints to prevent enqueuing duplicate jobs.
  Uniquness is based on a combination of `args`, `queue`, `worker`, `state` and insertion time. It
  is configured at the worker or job level using the following options:

  * `:period` — The number of seconds until a job is no longer considered duplicate. You should
    always specify a period.
  * `:fields` — The fields to compare when evaluating uniqueness. The available fields are
    `:args`, `:queue` and `:worker`, by default all three are used.
  * `:states` — The job states that will be checked for duplicates. The available states are
    `:available`, `:scheduled`, `:executing`, `:retryable` and `:completed`. By default all states
    are checked, which prevents _any_ duplicates, even if the previous job has been completed.

  For example, configure a worker to be unique across all fields and states for 60 seconds:

  ```elixir
  use Oban.Worker, unique: [period: 60]
  ```

  Configure the worker to be unique only by `:worker` and `:queue`:

  ```elixir
  use Oban.Worker, unique: [fields: [:queue, :worker], period: 60]
  ```

  Or, configure a worker to be unique until it has executed:

  ```elixir
  use Oban.Worker, unique: [period: 300, states: [:available, :scheduled, :executing]]
  ```

  ### Stronger Guarantees

  Oban's unique job support is built on a client side read/write cycle. That makes it subject to
  duplicate writes if two transactions are started simultaneously. If you _absolutely must_ ensure
  that a duplicate job isn't inserted then you will have to make use of unique constraints within
  the database. `Oban.insert/2,4` will handle unique constraints safely through upsert support.

  ### Performance Note

  If your application makes heavy use of unique jobs you may want to add indexes on the `args` and
  `inserted_at` columns of the `oban_jobs` table. The other columns considered for uniqueness are
  already covered by indexes.

  ## Customizing Backoff

  When jobs fail they may be retried again in the future using a backoff algorithm. By default
  the backoff is exponential with a fixed padding of 15 seconds. This may be too aggressive for
  jobs that are resource intensive or need more time between retries. To make backoff scheduling
  flexible a worker module may define a custom backoff function.

  This worker defines a backoff function that delays retries using a variant of the historic
  Resque/Sidekiq algorithm:

      defmodule MyApp.SidekiqBackoffWorker do
        use Oban.Worker

        @impl Worker
        def backoff(attempt) do
          :math.pow(attempt, 4) + 15 + :rand.uniform(30) * attempt
        end

        @impl Worker
        def perform(_args, _job) do
          :do_business
        end
      end

  Here are some alternative backoff strategies to consider:

  * **constant** — delay by a fixed number of seconds, e.g. 1→15, 2→15, 3→15
  * **linear** — delay for the same number of seconds as the current attempt, e.g. 1→1, 2→2, 3→3
  * **squared** — delay by attempt number squared, e.g. 1→1, 2→4, 3→9
  * **sidekiq** — delay by a base amount plus some jitter, e.g. 1→32, 2→61, 3→135
  """
  @moduledoc since: "0.1.0"

  alias Oban.Job

  @doc """
  Build a job changeset for this worker with optional overrides.

  See `Oban.Job.new/2` for the available options.
  """
  @callback new(args :: Job.args(), opts :: [Job.option()]) :: Ecto.Changeset.t()

  @doc """
  Calculate the execution backoff, or the number of seconds to wait before retrying a failed job.
  """
  @callback backoff(attempt :: pos_integer()) :: pos_integer()

  @doc """
  The `perform/2` function is called when the job is executed.

  The value returned from `perform/2` is ignored, unless it returns an `{:error, reason}` tuple.
  With an error return or when perform has an uncaught exception or throw then the error will be
  reported and the job will be retried (provided there are attempts remaining).
  """
  @callback perform(args :: Job.args(), job :: Job.t()) :: term()

  @doc false
  defmacro __using__(opts) do
    quote location: :keep do
      alias Oban.{Job, Worker}

      @after_compile Worker
      @behaviour Worker

      @doc false
      def __opts__ do
        Keyword.put(unquote(opts), :worker, to_string(__MODULE__))
      end

      @impl Worker
      def new(args, opts \\ []) when is_map(args) and is_list(opts) do
        Job.new(args, Keyword.merge(__opts__(), opts))
      end

      @impl Worker
      def backoff(attempt) when is_integer(attempt) do
        Worker.default_backoff(attempt)
      end

      defoverridable Worker
    end
  end

  @doc false
  defmacro __after_compile__(%{module: module}, _) do
    Enum.each(module.__opts__(), &validate_opt!/1)
  end

  @doc false
  @spec default_backoff(pos_integer(), non_neg_integer()) :: pos_integer()
  def default_backoff(attempt, base_backoff \\ 15) when is_integer(attempt) do
    trunc(:math.pow(2, attempt) + base_backoff)
  end

  defp validate_opt!({:max_attempts, max_attempts}) do
    unless is_integer(max_attempts) and max_attempts > 0 do
      raise ArgumentError, "expected :max_attempts to be a positive integer"
    end
  end

  defp validate_opt!({:queue, queue}) do
    unless is_atom(queue) or is_binary(queue) do
      raise ArgumentError, "expected :queue to be an atom or a binary, got: #{inspect(queue)}"
    end
  end

  defp validate_opt!({:unique, unique}) do
    unless is_list(unique) and Enum.all?(unique, &Job.valid_unique_opt?/1) do
      raise ArgumentError, "unexpected unique options: #{inspect(unique)}"
    end
  end

  defp validate_opt!({:worker, worker}) do
    unless is_binary(worker) do
      raise ArgumentError, "expected :worker to be a binary, got: #{inspect(worker)}"
    end
  end

  defp validate_opt!(option) do
    raise ArgumentError, "unknown option provided #{inspect(option)}"
  end
end
