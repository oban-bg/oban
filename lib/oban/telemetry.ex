defmodule Oban.Telemetry do
  @moduledoc """
  Telemetry integration for event metrics, logging and error reporting.

  ### Job Events

  Oban emits an event after a job executes: `[:oban, :success]` if the job succeeded or `[:oban,
  :failure]` if there was an error or the process crashed.

  All job events share the same details about the job that was executed. In addition, failed jobs
  provide the error type, the error itself, and the stacktrace. The following chart shows which
  metadata you can expect for each event:

  | event      | measures    | metadata                                                                     |
  | ---------- | ----------- | ---------------------------------------------------------------------------- |
  | `:success` | `:duration` | `:id, :args, :queue, :worker, :attempt, :max_attempts`                        |
  | `:failure` | `:duration` | `:id, :args, :queue, :worker, :attempt, :max_attempts, :kind, :error, :stack` |

  For `:failure` events the metadata includes details about what caused the failure. The `:kind`
  value is determined by how an error occurred. Here are the possible kinds:

  * `:error` — from an `{:error, error}` return value. Some Erlang functions may also throw an
    `:error` tuple, which will be reported as `:error`.
  * `:exception` — from a rescued exception
  * `:exit` — from a caught process exit
  * `:throw` — from a caught value, this doesn't necessarily mean that an error occurred and the
    error value is unpredictable

  ### Circuit Events

  All processes that interact with the database have circuit breakers to prevent errors from
  crashing the entire supervision tree. Processes emit a `[:oban, :trip_circuit]` event when a
  circuit is tripped and `[:oban, :open_circuit]` when the breaker is subsequently opened again.

  | event           | measures | metadata            |
  | --------------- | -------- | ------------------- |
  | `:trip_circuit` |          | `:name`, `:message` |
  | `:open_circuit` |          | `:name`             |

  Metadata

  * `:name` — the registered name of the process that tripped a circuit, i.e. `Oban.Notifier`
  * `:message` — a formatted error message describing what went wrong

  ## Default Logger

  A default log handler that emits structured JSON is provided, see `attach_default_logger/0` for
  usage. Otherwise, if you would prefer more control over logging or would like to instrument
  events you can write your own handler.

  ## Examples

  A handler that only logs a few details about failed jobs:

  ```elixir
  defmodule MicroLogger do
    require Logger

    def handle_event([:oban, :failure], %{duration: duration}, meta, nil) do
      Logger.warn("[#\{meta.queue}] #\{meta.worker} failed in #\{duration}")
    end
  end

  :telemetry.attach("oban-logger", [:oban, :failure], &MicroLogger.handle_event/4, nil)
  ```

  Another great use of execution data is error reporting. Here is an example of integrating with
  [Honeybadger][honey], but only reporting jobs that have failed 3 times or more:

  ```elixir
  defmodule ErrorReporter do
    def handle_event([:oban, :failure], _timing, %{attempt: attempt} = meta, nil) do
      if attempt >= 3 do
        context = Map.take(meta, [:id, :args, :queue, :worker])

        Honeybadger.notify(meta.error, context, meta.stack)
      end
    end
  end

  :telemetry.attach("oban-errors", [:oban, :failure], &ErrorReporter.handle_event/4, nil)
  ```

  [honey]: https://honeybadger.io
  """
  @moduledoc since: "0.4.0"

  require Logger

  @doc """
  Attaches a default structured JSON Telemetry handler for logging.

  This function attaches a handler that outputs logs with the following fields:

    * `source` — always "oban"
    * `event` — either `:success` or `:failure` dependening on whether the job succeeded or errored
    * `args` — a map of the job's raw arguments
    * `worker` — the job's worker module
    * `queue` — the job's queue
    * `duration` — the job's runtime duration in microseconds

  ## Examples

  Attach a logger at the default `:info` level:

      :ok = Oban.Telemetry.attach_default_logger()

  Attach a logger at the `:debug` level:

      :ok = Oban.Telemetry.attach_default_logger(:debug)
  """
  @doc since: "0.4.0"
  @spec attach_default_logger() :: :ok | {:error, :already_exists}
  def attach_default_logger(level \\ :info) do
    events = [
      [:oban, :success],
      [:oban, :failure],
      [:oban, :trip_circuit],
      [:oban, :open_circuit]
    ]

    :telemetry.attach_many("oban-default-logger", events, &handle_event/4, level)
  end

  @doc false
  @spec handle_event([atom()], map(), map(), Logger.level()) :: :ok
  def handle_event([:oban, event], measure, meta, level)
      when event in [:success, :failure] do
    log_message(
      level,
      %{
        source: "oban",
        event: event,
        args: meta[:args],
        worker: meta[:worker],
        queue: meta[:queue],
        duration: measure[:duration]
      }
    )
  end

  def handle_event([:oban, event], _measure, meta, level)
      when event in [:trip_circuit, :open_circuit] do
    log_message(level, Map.merge(meta, %{source: "oban", event: event}))
  end

  defp log_message(level, message) do
    Logger.log(level, fn -> Jason.encode!(message) end)
  end
end
