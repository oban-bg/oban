defmodule Oban.Telemetry do
  @moduledoc """
  Telemetry integration for event metrics, logging and error reporting.

  Oban currently emits an event when a job has exeucted: `[:oban, :success]` if the job succeeded
  or `[:oban, :failure]` if there was an error or the process crashed.

  All job events share the same details about the job that was executed. In addition, failed jobs
  provide the error type, the error itself, and the stacktrace. The following chart shows which
  metadata you can expect for each event:

  | event      | metadata                                                                     |
  | ---------- | ---------------------------------------------------------------------------- |
  | `:success` | `:id, :args, :queue, :worker, :attempt, :max_attempt`                        |
  | `:failure` | `:id, :args, :queue, :worker, :attempt, :max_attempt, :kind, :error, :stack` |

  For `:failure` events the metadata will include details about what caused the failure. The
  `:kind` value is determined by how an error occurred. Here are the possible kinds:

  * `:error` — from an `{:error, error}` return value. Some Erlang functions may also throw an
    `:error` tuple, which will be reported as `:error`.
  * `:exception` — from a rescued exception
  * `:exit` — from a caught process exit
  * `:throw` — from a caught value, this doesn't necessarily mean that an error occurred and the
    error value is unpredictable

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
      Logger.warning("[#\{meta.queue}] #\{meta.worker} failed in #\{duration}")
    end
  end

  :telemetry.attach("oban-logger", [:oban, :failure], &ObanLogger.handle_event/4, nil)
  ```

  Another great use of execution data is error reporting. Here is an example of integrating with
  [Honeybadger][honey], but only reporting jobs that have failed 3 times or more:

  ```elixir
  defmodule ErrorReporter do
    def handle_event([:oban, :failure], _timing, %{attempt: attempt}, nil) do
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

      :ok = Oban.Telemetry.attach_default_logger()
  """
  @doc since: "0.4.0"
  @spec attach_default_logger() :: :ok | {:error, :already_exists}
  def attach_default_logger do
    events = [[:oban, :success], [:oban, :failure]]

    :telemetry.attach_many("oban-default-logger", events, &handle_event/4, :no_config)
  end

  @doc false
  @spec handle_event([atom()], map(), map(), :no_config) :: :ok
  def handle_event([:oban, event], measurement, meta, :no_config)
      when event in [:success, :failure] do
    Logger.info(fn ->
      Jason.encode!(%{
        source: "oban",
        event: event,
        args: meta[:args],
        worker: meta[:worker],
        queue: meta[:queue],
        duration: measurement[:duration]
      })
    end)
  end
end
