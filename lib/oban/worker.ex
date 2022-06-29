defmodule Oban.Worker do
  @moduledoc """
  Defines a behavior and macro to guide the creation of worker modules.

  Worker modules do the work of processing a job. At a minimum they must define a `c:perform/1`
  function, which is called with the full `Oban.Job` struct.

  ## Defining Workers

  Worker modules are defined by using `Oban.Worker`. A bare `use Oban.Worker` invocation sets a
  worker with these defaults:

  * `:max_attempts` — 20
  * `:priority` — 0
  * `:queue` — `:default`
  * `:unique` — no uniqueness set

  To create a minimum worker using the defaults, including the `default` queue:

      defmodule MyApp.Workers.Basic do
        use Oban.Worker

        @impl Oban.Worker
        def perform(%Oban.Job{args: args}) do
          IO.inspect(args)
          :ok
        end
      end

  The following example defines a complex worker module to process jobs in the `events` queue.
  It then dials down the priority from 0 to 1, limits retrying on failures to 10 attempts, adds
  a "business" tag, and ensures that duplicate jobs aren't enqueued within a 30 second period:

      defmodule MyApp.Workers.Business do
        use Oban.Worker,
          queue: :events,
          priority: 1,
          max_attempts: 10,
          tags: ["business"],
          unique: [period: 30]

        @impl Oban.Worker
        def perform(%Oban.Job{attempt: attempt}) when attempt > 3 do
          IO.inspect(attempt)
        end

        def perform(job) do
          IO.inspect(job.args)
        end
      end

  The `c:perform/1` function receives an `Oban.Job` struct as an argument. This allows workers to
  change the behavior of `c:perform/1` based on attributes of the job, e.g. the args, number of
  execution attempts, or when it was inserted.

  The value returned from `c:perform/1` can control whether the job is a success or a failure:

  * `:ok` or `{:ok, value}` — the job is successful; for success tuples the `value` is ignored

  * `{:cancel, reason}` — cancel executing the job and stop retrying it. An error is recorded
    using the optional `reason`, though the job is still successful.

  * `{:error, error}` — the job failed, record the error and schedule a retry if possible

  * `{:snooze, seconds}` — mark the job as `snoozed` and schedule it to run again `seconds` in the
    future. See [Snoozing](#module-snoozing-jobs) for more details.

  In addition to explicit return values, any _unhandled exception_, _exit_ or _throw_ will fail
  the job and schedule a retry if possible.

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

  Note that `unique` options aren't merged, they are overridden entirely.

  See `Oban.Job` for all available options.

  ## Customizing Backoff

  When jobs fail they may be retried again in the future using a backoff algorithm. By default the
  backoff is exponential with a fixed padding of 15 seconds and a small amount of jitter. The
  jitter helps to prevent jobs that fail simultaneously from consistently retrying at the same
  time. The default backoff is clamped to a maximum of 12 days, the equivalent of the 20th
  attempt.

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

  ## Snoozing jobs

  When returning `{:snooze, snooze_time}` in `c:perform/1`, the job is postponed for at
  least `snooze_time` seconds. Snoozing is done by incrementing the job's `max_attempts` field and
  scheduling execution for `snooze_time` seconds in the future.

  Snoozing does not change the number of retries remaining on the job, but it does increment the `attempt`
  number each time the job snoozes, which will affect the default backoff exponential retry
  algorithm. In the example below the `c:backoff/1` callback compensates for snoozing:

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

  ## Limiting Execution Time

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

  Define the `timeout` value through job args:

      def timeout(%_{args: %{"timeout" => timeout}}), do: timeout

  Define the `timeout` based on the number of attempts:

      def timeout(%_{attempt: attempt}), do: attempt * :timer.seconds(5)
  """
  @moduledoc since: "0.1.0"

  import Kernel, except: [to_string: 1]

  alias Oban.{Backoff, Job}

  @type t :: module()
  @type result ::
          :ok
          | :discard
          | {:cancel, reason :: term()}
          | {:discard, reason :: term()}
          | {:ok, ignored :: term()}
          | {:error, reason :: term()}
          | {:snooze, seconds :: pos_integer()}

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
  @callback backoff(job :: Job.t()) :: pos_integer()

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

  Note that the `args` map provided to `perform/1` will _always_ have string keys, regardless of
  the key type when the job was enqueued. The `args` are stored as `jsonb` in PostgreSQL and the
  serialization process automatically stringifies all keys.
  """
  @callback perform(job :: Job.t()) :: result()

  @max_for_backoff 20
  @backoff_base 15

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
    Enum.each(module.__opts__(), &validate_opt!/1)
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
      if max_attempts <= @max_for_backoff do
        attempt
      else
        round(attempt / max_attempts * @max_for_backoff)
      end

    time = trunc(:math.pow(2, clamped_attempt) + @backoff_base)

    Backoff.jitter(time)
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
      {:error, %RuntimeError{message: "module is not a worker: #{inspect(module)}"}}
    end
  rescue
    ArgumentError ->
      {:error, %RuntimeError{message: "unknown worker: #{worker_name}"}}
  end

  # Validation Helpers

  defp validate_opt!({:max_attempts, max_attempts}) do
    unless is_integer(max_attempts) and max_attempts > 0 do
      raise ArgumentError,
            "expected :max_attempts to be a positive integer, got: #{inspect(max_attempts)}"
    end
  end

  defp validate_opt!({:priority, priority}) do
    unless is_integer(priority) and priority > -1 and priority < 4 do
      raise ArgumentError,
            "expected :priority to be an integer from 0 to 3, got: #{inspect(priority)}"
    end
  end

  defp validate_opt!({:queue, queue}) do
    unless is_atom(queue) or is_binary(queue) do
      raise ArgumentError, "expected :queue to be an atom or a binary, got: #{inspect(queue)}"
    end
  end

  defp validate_opt!({:tags, tags}) do
    unless is_list(tags) and Enum.all?(tags, &is_binary/1) do
      raise ArgumentError, "expected :tags to be a list of strings, got: #{inspect(tags)}"
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
