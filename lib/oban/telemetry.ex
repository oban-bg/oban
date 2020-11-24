defmodule Oban.Telemetry do
  @moduledoc """
  Telemetry integration for event metrics, logging and error reporting.

  ### Job Events

  Oban emits the following telemetry events for each job:

  * `[:oban, :job, :start]` — at the point a job is fetched from the database and will execute
  * `[:oban, :job, :stop]` — after a job succeeds and the success is recorded in the database
  * `[:oban, :job, :exception]` — after a job fails and the failure is recorded in the database

  All job events share the same details about the job that was executed. In addition, failed jobs
  provide the error type, the error itself, and the stacktrace. The following chart shows which
  metadata you can expect for each event:

  | event        | measures                   | metadata                                                                                                  |
  | ------------ | -------------------------- | ------------------------------------------- |
  | `:start`     | `:system_time`             | `:job, :prefix`                             |
  | `:stop`      | `:duration`, `:queue_time` | `:job, :prefix`                             |
  | `:exception` | `:duration`, `:queue_time` | `:job, :prefix, :kind, :error, :stacktrace` |

  For `:exception` events the metadata includes details about what caused the failure. The `:kind`
  value is determined by how an error occurred. Here are the possible kinds:

  * `:error` — from an `{:error, error}` return value. Some Erlang functions may also throw an
    `:error` tuple, which will be reported as `:error`.
  * `:exit` — from a caught process exit
  * `:throw` — from a caught value, this doesn't necessarily mean that an error occurred and the
    error value is unpredictable

  ### Producer Events

  Oban emits the following telemetry span events for each queue's producer:

  * `[:oban, :producer, :start | :stop | :exception]` — when a producer deschedules or dispatches
    new jobs

  | event        | measures       | metadata          |
  | ------------ | -------------- | ----------------- |
  | `:start`     | `:system_time` | `:action, :queue` |
  | `:stop`      | `:duration`    | `:action, :queue` |
  | `:exception` | `:duration`    | `:action, :queue` |

  Metadata

  * `:action` — one of `:deschedule` or `:dispatch`
  * `:queue` — the name of the queue as a string, e.g. "default" or "mailers"

  ### Circuit Events

  All processes that interact with the database have circuit breakers to prevent errors from
  crashing the entire supervision tree. Processes emit a `[:oban, :circuit, :trip]` event when a
  circuit is tripped and `[:oban, :circuit, :open]` when the breaker is subsequently opened again.

  | event                      | measures | metadata                               |
  | -------------------------- | -------- | -------------------------------------- |
  | `[:oban, :circuit, :trip]` |          | `:error, :message, :name, :stacktrace` |
  | `[:oban, :circuit, :open]` |          | `:name`                                |

  Metadata

  * `:error` — the error that tripped the circuit, see the error kinds breakdown above
  * `:name` — the registered name of the process that tripped a circuit, i.e. `Oban.Notifier`
  * `:message` — a formatted error message describing what went wrong
  * `:stacktrace` — exception stacktrace, when available

  ## Default Logger

  A default log handler that emits structured JSON is provided, see `attach_default_logger/0` for
  usage. Otherwise, if you would prefer more control over logging or would like to instrument
  events you can write your own handler.

  Here is an example of the JSON output for the `job:stop` event:

  ```json
  {
    "args":{"action":"OK","ref":1},
    "duration":4327295,
    "event":"job:stop",
    "queue":"alpha",
    "queue_time":3127905,
    "source":"oban",
    "worker":"Oban.Integration.Worker"
  }
  ```

  All timing measurements are recorded as native time units but logged in microseconds.

  ## Examples

  A handler that only logs a few details about failed jobs:

  ```elixir
  defmodule MicroLogger do
    require Logger

    def handle_event([:oban, :job, :exception], %{duration: duration}, meta, nil) do
      Logger.warn("[#\{meta.queue}] #\{meta.worker} failed in #\{duration}")
    end
  end

  :telemetry.attach("oban-logger", [:oban, :job, :exception], &MicroLogger.handle_event/4, nil)
  ```

  Another great use of execution data is error reporting. Here is an example of integrating with
  [Honeybadger][honey], but only reporting jobs that have failed 3 times or more:

  ```elixir
  defmodule ErrorReporter do
    def handle_event([:oban, :job, :exception], _, %{attempt: attempt} = meta, _) do
      if attempt >= 3 do
        context = Map.take(meta, [:id, :args, :queue, :worker])

        Honeybadger.notify(meta.error, context, meta.stacktrace)
      end
    end
  end

  :telemetry.attach("oban-errors", [:oban, :job, :exception], &ErrorReporter.handle_event/4, [])
  ```

  [honey]: https://honeybadger.io
  """
  @moduledoc since: "0.4.0"

  require Logger

  @doc """
  Attaches a default structured JSON Telemetry handler for logging.

  This function attaches a handler that outputs logs with the following fields:

  * `args` — a map of the job's raw arguments
  * `duration` — the job's runtime duration, in the native time unit
  * `event` — either `:success` or `:failure` depending on whether the job succeeded or errored
  * `queue` — the job's queue
  * `source` — always "oban"
  * `system_time` — when the job started, in microseconds
  * `worker` — the job's worker module

  ## Examples

  Attach a logger at the default `:info` level:

      :ok = Oban.Telemetry.attach_default_logger()

  Attach a logger at the `:debug` level:

      :ok = Oban.Telemetry.attach_default_logger(:debug)
  """
  @doc since: "0.4.0"
  @spec attach_default_logger(Logger.level()) :: :ok | {:error, :already_exists}
  def attach_default_logger(level \\ :info) do
    events = [
      [:oban, :job, :start],
      [:oban, :job, :stop],
      [:oban, :job, :exception],
      [:oban, :circuit, :trip],
      [:oban, :circuit, :open]
    ]

    :telemetry.attach_many("oban-default-logger", events, &handle_event/4, level)
  end

  @doc """
  Measure and report `:start`, `:stop` and `:exception` events for a function.

  ## Examples

  Emit span timing events for a prune function:

      :ok = Oban.Telemetry.span(:prune, &MyApp.Pruner.prune/0, %{extra: :data})

  That will emit the following events:

  * `[:oban, :prune, :start]` — before the function is invoked
  * `[:oban, :prune, :stop]` — when the function completes successfully
  * `[:oban, :prune, :exception]` — reported if the function throws, crashes or raises an error
  """
  @spec span(name :: atom(), fun :: (() -> term()), meta :: map()) :: term()
  def span(name, fun, meta \\ %{}) when is_atom(name) and is_function(fun, 0) do
    start_time = System.system_time()
    start_mono = System.monotonic_time()

    execute([:oban, name, :start], %{system_time: start_time}, meta)

    try do
      result = fun.()

      execute([:oban, name, :stop], %{duration: duration(start_mono)}, meta)

      result
    catch
      kind, reason ->
        execute(
          [:oban, name, :exception],
          %{duration: duration(start_mono)},
          Map.merge(meta, %{kind: kind, reason: reason, stacktrace: __STACKTRACE__})
        )

        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  defp duration(start_mono), do: System.monotonic_time() - start_mono

  @doc false
  def execute(event_name, measurements, meta) do
    :telemetry.execute(event_name, measurements, normalize_meta(meta))
  end

  defp normalize_meta(%{name: {:via, Registry, {Oban.Registry, {_pid, name}}}} = meta) do
    name =
      with {role, name} <- name do
        Module.concat([
          Oban.Queue,
          Macro.camelize(to_string(name)),
          Macro.camelize(to_string(role))
        ])
      end

    %{meta | name: name}
  end

  defp normalize_meta(meta), do: meta

  @doc false
  @spec handle_event([atom()], map(), map(), Logger.level()) :: :ok
  def handle_event([:oban, :job, event], measure, meta, level) do
    meta
    |> Map.take([:args, :worker, :queue])
    |> Map.merge(converted_measurements(measure))
    |> log_message("job:#{event}", level)
  end

  def handle_event([:oban, :circuit, event], _measure, meta, level) do
    meta
    |> Map.take([:message, :name])
    |> log_message("circuit:#{event}", level)
  end

  defp converted_measurements(measure) do
    for {key, val} <- measure, key in [:duration, :queue_time], into: %{} do
      {key, System.convert_time_unit(val, :native, :microsecond)}
    end
  end

  defp log_message(message, event, level) do
    Logger.log(level, fn ->
      message
      |> Map.put(:event, event)
      |> Map.put(:source, "oban")
      |> Jason.encode_to_iodata!()
    end)
  end
end
