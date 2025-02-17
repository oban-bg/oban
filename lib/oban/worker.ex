defmodule Oban.Worker do
  @moduledoc """
  Defines a behavior and macro to guide the creation of worker modules.

  Worker modules do the work of processing a job. At a minimum they must define a `c:perform/1`
  function, which is called with the full `Oban.Job` struct.

  ## Defining Workers

  Worker modules are defined by using `Oban.Worker`. `use Oban.Worker` supports the following
  options:

  * `:max_attempts` — Integer specifying how many times the job will be retried. Defaults to `20`
  * `:priority` — Integer from 0 (highest priority) to 9 (lowest priority). Defaults to `0`
  * `:queue` — Name of a queue as an atom. Defaults to `:default`
  * `:tags` — A list of strings representing the tags to associate with jobs. Defaults to `[]`
  * `:replace` — A nested list of job statuses and fields to be replaced when a job is executed.
    Defaults to `[]`
  * `:unique` — a keyword list that determines how jobs are uniquely identified. It may be `true`
    to enable uniqueness with the default options, or `false` to explicitly disable uniqueness.
    Defaults to `false`

  The following is a basic workers that uses the defaults:

      defmodule MyApp.Workers.Basic do
        use Oban.Worker

        @impl Oban.Worker
        def perform(%Oban.Job{args: args}) do
          IO.inspect(args)
          :ok
        end
      end

  Which is equivalent to this worker, which sets all options explicitly:

      defmodule MyApp.Workers.Basic do
        use Oban.Worker,
          max_attempts: 20,
          priority: 0,
          queue: :default,
          tags: [],
          replace: [],
          unique: false

        @impl Oban.Worker
        def perform(%Oban.Job{args: args}) do
          IO.inspect(args)
          :ok
        end
      end

  The following example defines a complex worker module to process jobs in the `events` queue.
  It then dials down the priority from `0` to `1`, limits retrying on failures to ten attempts,
  adds a `business` tag, and ensures that duplicate jobs aren't enqueued within a
  30 second period:

      defmodule MyApp.Workers.Business do
        use Oban.Worker,
          queue: :events,
          priority: 1,
          max_attempts: 10,
          tags: ["business"],
          replace: [scheduled: [:scheduled_at]],
          unique: [period: 30]

        @impl Oban.Worker
        def perform(%Oban.Job{attempt: attempt}) when attempt > 3 do
          IO.inspect(attempt)
        end

        def perform(job) do
          IO.inspect(job.args)
        end
      end

  > #### Options at Compile-Time {: .warning}
  >
  > Like all `use` macros, options are defined at compile time. Avoid using
  > `Application.get_env/2` to define worker options. Instead, pass dynamic options at runtime
  > by passing them to the worker's `c:new/2` function:
  >
  > ```elixir
  > MyApp.MyWorker.new(args, queue: dynamic_queue)
  > ```

  The `c:perform/1` function receives an `Oban.Job` struct as an argument. This allows workers to
  change the behavior of `c:perform/1` based on attributes of the job, such as the args, number of
  execution attempts, or when it was inserted.

  The value returned from `c:perform/1` can control whether the job is a success or a failure:

  * `:ok` or `{:ok, value}` — the job is successful and marked as `completed`.  The `value` from
    success tuples is ignored.

  * `{:cancel, reason}` — cancel executing the job and stop retrying it. An error is recorded
    using the provided `reason`. The job is marked as `cancelled`.

  * `{:error, error}` — the job failed, record the error. If `max_attempts` has not been reached
    already, the job is marked as `retryable` and scheduled to run again. Otherwise, the job is
    marked as `discarded` and won't be retried.

  * `{:snooze, seconds}` — mark the job as `snoozed` and schedule it to run again `seconds` in the
    future. See [Snoozing](#module-snoozing-jobs) for more details.

  In addition to explicit return values, any _unhandled exception_, _exit_ or _throw_ will fail
  the job and schedule a retry under the same conditions as in the `{:error, error}` case.

  As an example of error tuple handling, this worker will return an error tuple when the `value`
  is less than one:

      defmodule MyApp.Workers.ErrorExample do
        use Oban.Worker

        @impl Worker
        def perform(%{args: %{"value" => value}}) do
          if value > 1 do
            :ok
          else
            {:error, "invalid value given: " <> inspect(value)}
          end
        end
      end

  The error tuple is wrapped in an `Oban.PerformError` with a formatted message. The error tuple
  itself is available through the exception's `:reason` field.

  ## Enqueuing Jobs

  All workers implement a `c:new/2` function that converts an args map into a job changeset
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

  `unique` options aren't merged, they are overridden entirely.

  You can also insert multiple jobs within a single transaction—see
  `Oban.insert/5`.

  Jobs that are inserted are executed as soon as possible by default. If you need
  to **schedule** jobs in the future, see the guide for [*Scheduling Jobs*](scheduling_jobs.html).

  See `Oban.Job` for all available options, and the
  [*Unique Jobs* guide](unique_jobs.html) for more information about unique jobs.

  ## Customizing Backoff

  When jobs fail they may be retried again in the future using a backoff algorithm. By default the
  backoff is exponential with a fixed padding of 15 seconds and a small amount of jitter. The
  jitter helps to prevent jobs that fail simultaneously from consistently retrying at the same
  time. With the default backoff behavior the 20th attempt will occur around 12 days after the
  19th attempt, and a total of 25 days after the first attempt.

  If the default strategy is too aggressive or otherwise unsuited to your app's workload you can
  define a custom backoff function using the `c:backoff/1` callback.

  The following worker defines a `c:backoff/1` function that delays retries using a variant of the
  historic Resque/Sidekiq algorithm:

      defmodule MyApp.SidekiqBackoffWorker do
        use Oban.Worker

        @impl Worker
        def backoff(%Job{attempt: attempt}) do
          trunc(:math.pow(attempt, 4) + 15 + :rand.uniform(30) * attempt)
        end

        @impl Worker
        def perform(_job) do
          :do_business
        end
      end

  Here are some alternative backoff strategies to consider:

  * **constant** — delay by a fixed number of seconds, e.g. 1→15, 2→15, 3→15
  * **linear** — delay for the same number of seconds as the current attempt, e.g. 1→1, 2→2, 3→3
  * **squared** — delay by attempt number squared, e.g. 1→1, 2→4, 3→9
  * **sidekiq** — delay by a base amount plus some jitter, e.g. 1→32, 2→61, 3→135

  ### Contextual Backoff

  Any error, catch or throw is temporarily recorded in the job's `unsaved_error` map. The unsaved
  error map can be used by `c:backoff/1` to calculate a custom backoff based on the exact error
  that failed the job. In this example the `c:backoff/1` callback checks to see if the error was
  due to rate limiting and adjusts the backoff accordingly:

      defmodule MyApp.ApiWorker do
        use Oban.Worker

        @five_minutes 5 * 60

        @impl Worker
        def perform(%{args: args}) do
          MyApp.make_external_api_call(args)
        end

        @impl Worker
        def backoff(%Job{attempt: attempt, unsaved_error: unsaved_error}) do
          %{kind: _, reason: reason, stacktrace: _} = unsaved_error

          case reason do
            %MyApp.ApiError{status: 429} -> @five_minutes
            _ -> trunc(:math.pow(attempt, 4))
          end
        end
      end

  ## Execution Timeout

  By default, individual jobs may execute indefinitely. If this is undesirable you may define a
  timeout in milliseconds with the `c:timeout/1` callback on your worker module.

  For example, to limit a worker's execution time to 30 seconds:

      def MyApp.Worker do
        use Oban.Worker

        @impl Oban.Worker
        def perform(_job) do
          something_that_may_take_a_long_time()

          :ok
        end

        @impl Oban.Worker
        def timeout(_job), do: :timer.seconds(30)
      end

  The `c:timeout/1` function accepts an `Oban.Job` struct, so you can customize the timeout using
  any job attributes.

  For example, you can define the `timeout` value through job args:

      def timeout(%_{args: %{"timeout" => timeout}}), do: timeout

  Or you can define the `timeout` based on the number of attempts:

      def timeout(%_{attempt: attempt}), do: attempt * :timer.seconds(5)


  If the job fails to execute before the timeout period then it will error with a dedicated
  `Oban.TimeoutError` exception. Timeouts are treated like any other failure and the job will be
  retried as usual if more attempts are available.

  ## Snoozing Jobs

  When returning `{:snooze, snooze_time}` in `c:perform/1`, the job is postponed for at least
  `snooze_time` seconds. Snoozing is done by incrementing the job's `max_attempts` field and
  scheduling execution for `snooze_time` seconds in the future.

  Executing bumps a job's `attempt` count. Despite snooze incrementing the `max_attempts` to
  preserve total retries, the change to `attempt` will affect the default backoff retry
  algorithm.

  > #### 🌟 Snoozes and Attempts {: .info}
  >
  > Oban Pro's [Smart Engine](https://oban.pro/docs/pro/Oban.Pro.Engines.Smart.html) rolls back
  > the `attempt` and preserves the original `max_attempts` in order to differentiate between
  > "real" attempts and snoozes, which keeps backoff calculation accurate.
  >
  > Without attempt correction you may need a solution that compensates for snoozing, such as the
  > example below:

      defmodule MyApp.SnoozingWorker do
        @max_attempts 20

        use Oban.Worker, max_attempts: @max_attempts

        @impl Worker
        def backoff(%Job{} = job) do
          corrected_attempt = @max_attempts - (job.max_attempts - job.attempt)

          Worker.backoff(%{job | attempt: corrected_attempt})
        end

        @impl Worker
        def perform(job) do
          if MyApp.something?(job), do: :ok, else: {:snooze, 60}
        end
      end

  ## Workers in A Different Application

  Occasionally, you may need to insert a job for a worker that exists in another
  application. In that case you can use `Oban.Job.new/2` to build the changeset
  manually:

      %{id: 1, user_id: 2}
      |> Oban.Job.new(queue: :default, worker: OtherApp.Worker)
      |> Oban.insert()

  ## Prioritizing Jobs

  Normally, all available jobs within a queue are executed in the order they were scheduled.
  You can override the normal behavior and prioritize or de-prioritize a job by
  assigning a numerical `:priority`.

    * Priorities from `0` to `9` are allowed, where `0` is the *highest* priority and `9`
      is the *lowest*.
    * The default priority is `0`; unless specified, all jobs have an equally high priority.
    * All jobs with a higher priority will execute before any jobs with a lower priority.
      Jobs with the *same priority* are executed in their scheduled order.

  ### Caveats & Guidelines

  The default priority is defined in the `jobs` table. The least intrusive way to change
  it for all jobs is to change the column default through a migration:

      alter table("oban_jobs") do
        modify :priority, :integer, default: 1, from: {:integer, default: 0}
      end

  """
  @moduledoc since: "0.1.0"

  import Kernel, except: [to_string: 1]

  alias Oban.{Backoff, Job, Validation}

  @type t :: module()

  @typedoc """
  Return values control whether a job is treated as a success or a failure.

  - `:ok` - the job is successful and marked as `completed`.
  - `{:ok, ignored}` - the job is successful, marked as `completed`, and the return value is ignored.
  - `{:cancel, reason}` - the job is marked as `cancelled` for the provided reason and no longer retried.
  - `{:error, reason}` - the job is marked as `retryable` for the provided reason, or `discarded`
    if it has  exhausted all attempts.
  - `{:snooze, seconds}` - mark the job as `scheduled` to run again `seconds` in the future.

  > #### Deprecated {: .warning}
  >
  > - `:discard` - deprecated, use `{:cancel, reason}` instead.
  > - `{:discard, reason}` - deprecated, use `{:cancel, reason}` instead.
  """
  @type result ::
          :ok
          | :discard
          | {:cancel, reason :: term()}
          | {:discard, reason :: term()}
          | {:ok, ignored :: term()}
          | {:error, reason :: term()}
          | {:snooze, seconds :: non_neg_integer()}

  @doc """
  Build a job changeset for this worker with optional overrides.

  See `Oban.Job.new/2` for the available options.
  """
  @callback new(args :: Job.args(), opts :: [Job.option()]) :: Job.changeset()

  @doc """
  Calculate the execution backoff.

  In this context backoff specifies the number of seconds to wait before retrying a failed job.

  Defaults to an exponential algorithm with a minimum delay of 15 seconds and a small amount of
  jitter.
  """
  @callback backoff(job :: Job.t()) :: non_neg_integer()

  @doc """
  Set a job's maximum execution time in milliseconds.

  Jobs that exceed the time limit are considered a failure and may be retried.

  Defaults to `:infinity`.
  """
  @callback timeout(job :: Job.t()) :: :infinity | pos_integer()

  @doc """
  The `c:perform/1` function is called to execute a job.

  Each `c:perform/1` function should return `:ok` or a success tuple. When the return is an error
  tuple, an uncaught exception or a throw then the error is recorded and the job may be retried if
  there are any attempts remaining.

  > #### `args` Are Stored as JSON {: .info}
  >
  > The `args` map provided to `perform/1` will _always_ have string keys, regardless of
  > the key type when the job was enqueued. The `args` are stored as `jsonb` in PostgreSQL and the
  > serialization process automatically stringifies all keys. Because `args` are always encoded
  > as JSON, you must also ensure that all values are serializable, otherwise you'll have
  > encoding errors when inserting jobs.

  """
  @callback perform(job :: Job.t()) :: result()

  @clamped_max 20

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
        Job.new(args, Worker.merge_opts(__opts__(), opts))
      end

      @impl Worker
      def backoff(%Job{} = job) do
        Worker.backoff(job)
      end

      @impl Worker
      def timeout(%Job{} = job) do
        Worker.timeout(job)
      end

      defoverridable Worker
    end
  end

  @doc false
  defmacro __after_compile__(%{module: module}, _env) do
    Validation.validate_schema!(module.__opts__(),
      max_attempts: :pos_integer,
      priority: {:range, 0..9},
      queue: {:or, [:atom, :string]},
      replace: {:custom, &Job.validate_replace/1},
      tags: {:list, :string},
      unique: {:custom, &Job.validate_unique/1},
      worker: :string
    )
  end

  @doc false
  def merge_opts(base_opts, opts) do
    Keyword.merge(base_opts, opts, fn
      :unique, [_ | _] = opts_1, [_ | _] = opts_2 ->
        Keyword.merge(opts_1, opts_2)

      _key, _opts, opts_2 ->
        opts_2
    end)
  end

  @doc false
  def backoff(%Job{attempt: attempt, max_attempts: max_attempts}) do
    clamped_attempt =
      if max_attempts <= @clamped_max do
        attempt
      else
        round(attempt / max_attempts * @clamped_max)
      end

    clamped_attempt
    |> Backoff.exponential(mult: 1, max_pow: 100, min_pad: 15)
    |> Backoff.jitter(mode: :inc)
  end

  @doc false
  def timeout(%Job{} = _job) do
    :infinity
  end

  @doc """
  Return a string representation of a worker module.

  This is particularly useful for normalizing worker names when building custom Ecto queries.

  ## Examples

      iex> Oban.Worker.to_string(MyApp.SomeWorker)
      "MyApp.SomeWorker"

      iex> Oban.Worker.to_string(Elixir.MyApp.SomeWorker)
      "MyApp.SomeWorker"

      iex> Oban.Worker.to_string("Elixir.MyApp.SomeWorker")
      "MyApp.SomeWorker"
  """
  @doc since: "2.1.0"
  @spec to_string(module() | String.t()) :: String.t()
  def to_string(worker) when is_atom(worker) and not is_nil(worker) do
    worker
    |> Kernel.to_string()
    |> to_string()
  end

  def to_string("Elixir." <> val), do: val
  def to_string(worker) when is_binary(worker), do: worker

  @doc """
  Resolve a module from a worker string.

  ## Examples

      iex> Oban.Worker.from_string("Oban.Integration.Worker")
      {:ok, Oban.Integration.Worker}

      iex> defmodule NotAWorker, do: []
      ...> Oban.Worker.from_string("NotAWorker")
      {:error, %RuntimeError{message: "module is not a worker: NotAWorker"}}

      iex> Oban.Worker.from_string("RandomWorker")
      {:error, %RuntimeError{message: "unknown worker: RandomWorker"}}
  """
  @doc since: "2.3.0"
  @spec from_string(String.t()) :: {:ok, module()} | {:error, Exception.t()}
  def from_string(worker_name) when is_binary(worker_name) do
    module =
      worker_name
      |> String.split(".")
      |> Module.safe_concat()

    if Code.ensure_loaded?(module) && function_exported?(module, :perform, 1) do
      {:ok, module}
    else
      {:error, RuntimeError.exception("module is not a worker: #{inspect(module)}")}
    end
  rescue
    ArgumentError ->
      {:error, RuntimeError.exception("unknown worker: #{worker_name}")}
  end
end
