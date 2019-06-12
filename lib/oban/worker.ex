defmodule Oban.Worker do
  @moduledoc """
  Defines a behavior and macro to guide the creation of worker modules.

  Worker modules do the work of processing a job. At a minimum they must define a `perform/1`
  function, which will be called with an `args` map.

  ## Defining Workers

  Define a worker to process jobs in the `events` queue:

      defmodule MyApp.Workers.Business do
        use Oban.Worker, queue: "events", max_attempts: 10

        @impl true
        def perform(args) do
          IO.inspect(args)
        end
      end

  The `perform/1` function will always receive the jobs `args` map. In this example the worker
  will simply inspect any arguments that are provided. Note that the return value isn't important.
  If `perform/1` returns without raising an exception the job is considered complete.

  ## Enqueuing Jobs

  All workers implement a `new/2` function that converts an args map into a job changeset
  suitable for inserting into the database for later execution:

      %{in_the: "business", of_doing: "business"}
      |> MyApp.Workers.Business.new()
      |> MyApp.Repo.insert()

  The worker's defaults may be overridden by passing options:

      %{vote_for: "none of the above"}
      |> MyApp.Workers.Business.new(queue: "special", max_attempts: 5)
      |> MyApp.Repo.insert()

  See `Oban.Job` for all available options.

  ## Customizing Backoff

  When jobs fail they may be retried again in the future using a backoff algorithm. By default
  the backoff is exponential with a fixed padding of 15 seconds. This may be too aggressive for
  jobs that are resource intensive or need more time between retries. To make backoff scheduling
  flexible a worker module may define a custom backoff function.

  This worker defines a backoff function that delays retries using a variant of the historic
  Resque/Sidekiq algorithm:

      defmodule MyApp.SidekiqBackoffWorker do
        use Oban.Worker

        @impl true
        def backoff(attempt) do
          :math.pow(attempt, 4) + 15 + :rand.uniform(30) * attempt
        end

        @impl true
        def perform(args) do
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
  The `perform/1` function is called when the job is executed.

  The function is passed a job's args, which is always a map with string keys.

  The return value is not important. If the function executes without raising an exception it is
  considered a success. If the job raises an exception it is a failure and the job may be
  scheduled for a retry.
  """
  @callback perform(args :: map()) :: term()

  @doc false
  defmacro __using__(opts) do
    quote location: :keep do
      alias Oban.{Job, Worker}

      @behaviour Worker

      @opts unquote(opts)
            |> Keyword.take([:queue, :max_attempts])
            |> Keyword.put(:worker, to_string(__MODULE__))

      @impl Worker
      def new(args, opts \\ []) when is_map(args) do
        Job.new(args, Keyword.merge(@opts, opts))
      end

      @impl Worker
      def backoff(attempt) when is_integer(attempt) do
        Worker.default_backoff(attempt)
      end

      @impl Worker
      def perform(args) when is_map(args) do
        :ok
      end

      defoverridable Worker
    end
  end

  @doc false
  @spec default_backoff(pos_integer(), non_neg_integer()) :: pos_integer()
  def default_backoff(attempt, base_backoff \\ 15) when is_integer(attempt) do
    trunc(:math.pow(2, attempt) + base_backoff)
  end
end
