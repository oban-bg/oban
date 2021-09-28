defmodule Oban.Telemetry do
  @moduledoc """
  Telemetry integration for event metrics, logging and error reporting.

  ### Initialization Events

  Oban emits the following telemetry event when an Oban supervisor is started:

  * `[:oban, :supervisor, :init]` - when the Oban supervisor is started this will execute

  The initialization event contains the following measurements:

  * `:system_time` - The system's time when Oban was started

  The initialization event contains the following metadata:

  * `:conf` - The configuration used for the Oban supervisor instance
  * `:pid` - The PID of the supervisor instance

  ### Job Events

  Oban emits the following telemetry events for each job:

  * `[:oban, :job, :start]` — at the point a job is fetched from the database and will execute
  * `[:oban, :job, :stop]` — after a job succeeds and the success is recorded in the database
  * `[:oban, :job, :exception]` — after a job fails and the failure is recorded in the database

  All job events share the same details about the job that was executed. In addition, failed jobs
  provide the error type, the error itself, and the stacktrace. The following chart shows which
  metadata you can expect for each event:

  | event        | measures                   | metadata                                          |
  | ------------ | -------------------------- | ------------------------------------------------- |
  | `:start`     | `:system_time`             | `:job, :conf, :state`                             |
  | `:stop`      | `:duration`, `:queue_time` | `:job, :conf, :state, :result`                    |
  | `:exception` | `:duration`, `:queue_time` | `:job, :conf, :state, :kind, :reason, :stacktrace` |

  Metadata

  * `:conf` — the config of the Oban supervised producer
  * `:job` — the executing `Oban.Job`
  * `:state` — one of `:success`, `:discard` or `:snoozed`
  * `:result` — the `perform/1` return value, only included when the state is `:success`

  For `:exception` events the metadata includes details about what caused the failure. The `:kind`
  value is determined by how an error occurred. Here are the possible kinds:

  * `:error` — from an `{:error, error}` return value. Some Erlang functions may also throw an
    `:error` tuple, which will be reported as `:error`.
  * `:exit` — from a caught process exit
  * `:throw` — from a caught value, this doesn't necessarily mean that an error occurred and the
    error value is unpredictable

  ### Producer Events

  Oban emits the following telemetry span events for each queue's producer:

  * `[:oban, :producer, :start | :stop | :exception]` — when a producer dispatches new jobs

  | event        | measures       | metadata                                      |
  | ------------ | -------------- | --------------------------------------------- |
  | `:start`     | `:system_time` | `:queue, :conf`                               |
  | `:stop`      | `:duration`    | `:queue, :conf, :dispatched_count`            |
  | `:exception` | `:duration`    | `:queue, :conf`, :kind, :reason, :stacktrace  |

  Metadata

  * `:queue` — the name of the queue as a string, e.g. "default" or "mailers"
  * `:conf` — the config of the Oban supervised producer
  * `:dispatched_count` — the number of jobs fetched and started by the producer

  ### Engine Events

  Oban emits telemetry span events for the following Engine operations:

  * `[:oban, :engine, :init, :start | :stop | :exception]`

  | event        | measures       | metadata           |
  | ------------ | -------------- | ------------------ |
  | `:start`     | `:system_time` | `:conf`, `engine`  |
  | `:stop`      | `:duration`    | `:conf`, `engine`  |
  | `:exception` | `:duration`    | `:conf`, `engine`  |

  * `[:oban, :engine, :refresh, :start | :stop | :exception]`

  | event        | measures       | metadata           |
  | ------------ | -------------- | ------------------ |
  | `:start`     | `:system_time` | `:conf`, `engine`  |
  | `:stop`      | `:duration`    | `:conf`, `engine`  |
  | `:exception` | `:duration`    | `:conf`, `engine`  |

  * `[:oban, :engine, :put_meta, :start | :stop | :exception]`

  | event        | measures       | metadata           |
  | ------------ | -------------- | ------------------ |
  | `:start`     | `:system_time` | `:conf`, `engine`  |
  | `:stop`      | `:duration`    | `:conf`, `engine`  |
  | `:exception` | `:duration`    | `:conf`, `engine`  |

  * `[:oban, :engine, :fetch_jobs, :start | :stop | :exception]`

  | event        | measures       | metadata           |
  | ------------ | -------------- | ------------------ |
  | `:start`     | `:system_time` | `:conf`, `engine`  |
  | `:stop`      | `:duration`    | `:conf`, `engine`  |
  | `:exception` | `:duration`    | `:conf`, `engine`  |


  * `[:oban, :engine, :complete_job, :start | :stop | :exception]`

  | event        | measures       | metadata                                                 |
  | ------------ | -------------- | -------------------------------------------------------  |
  | `:start`     | `:system_time` | `:conf`, `engine`, `job`                                 |
  | `:stop`      | `:duration`    | `:conf`, `engine`, `job`                                 |
  | `:exception` | `:duration`    | `:conf`, `engine`, `job`, `kind`, `reason`, `stacktrace` |

  * `[:oban, :engine, :discard_job, :start | :stop | :exception]`

  | event        | measures       | metadata                                                 |
  | ------------ | -------------- | -------------------------------------------------------  |
  | `:start`     | `:system_time` | `:conf`, `engine`, `job`                                 |
  | `:stop`      | `:duration`    | `:conf`, `engine`, `job`                                 |
  | `:exception` | `:duration`    | `:conf`, `engine`, `job`, `kind`, `reason`, `stacktrace` |

  * `[:oban, :engine, :error_job, :start | :stop | :exception]`

  | event        | measures       | metadata                                                 |
  | ------------ | -------------- | -------------------------------------------------------  |
  | `:start`     | `:system_time` | `:conf`, `engine`, `job`                                 |
  | `:stop`      | `:duration`    | `:conf`, `engine`, `job`                                 |
  | `:exception` | `:duration`    | `:conf`, `engine`, `job`, `kind`, `reason`, `stacktrace` |

  * `[:oban, :engine, :snooze_job, :start | :stop | :exception]`

  | event        | measures       | metadata                                                 |
  | ------------ | -------------- | -------------------------------------------------------  |
  | `:start`     | `:system_time` | `:conf`, `engine`, `job`                                 |
  | `:stop`      | `:duration`    | `:conf`, `engine`, `job`                                 |
  | `:exception` | `:duration`    | `:conf`, `engine`, `job`, `kind`, `reason`, `stacktrace` |

  * `[:oban, :engine, :cancel_job, :start | :stop | :exception]`

  | event        | measures       | metadata                                                 |
  | ------------ | -------------- | -------------------------------------------------------  |
  | `:start`     | `:system_time` | `:conf`, `engine`, `job`                                 |
  | `:stop`      | `:duration`    | `:conf`, `engine`, `job`                                 |
  | `:exception` | `:duration`    | `:conf`, `engine`, `job`, `kind`, `reason`, `stacktrace` |

  * `[:oban, :engine, :cancel_all_jobs, :start | :stop | :exception]`

  | event        | measures       | metadata                                                 |
  | ------------ | -------------- | ------------------------------------------------- |
  | `:start`     | `:system_time` | `:conf`, `engine`                                 |
  | `:stop`      | `:duration`    | `:conf`, `engine`                                 |
  | `:exception` | `:duration`    | `:conf`, `engine`, `kind`, `reason`, `stacktrace` |

  Metadata

  * `:conf` — the config of the Oban supervised producer
  * `:engine` — the module of the engine used
  * `:job` - the `Oban.Job` in question

  ### Notifier Events

  Oban emits telemetry a span event each time the Notifier is triggered:

  * `[:oban, :notifier, :notify, :start | :stop | :exception]`

  | event        | measures       | metadata                                                       |
  | ------------ | -------------- | -------------------------------------------------------------- |
  | `:start`     | `:system_time` | `:conf`, `channel`, `payload`                                  |
  | `:stop`      | `:duration`    | `:conf`, `channel`, `payload`                                  |
  | `:exception` | `:duration`    | `:conf`, `channel`, `payload`, `kind`, `reason`, `stacktrace`  |

  * `:conf` — the config of the Oban supervised producer
  * `:channel` — the channel on which the notification was sent
  * `:payload` - the payload that was sent
  * `kind`, `reason`, `stacktrace`, see the explanation above.

  ### Circuit Events

  All processes that interact with the database have circuit breakers to prevent errors from
  crashing the entire supervision tree. Processes emit a `[:oban, :circuit, :trip]` event when a
  circuit is tripped and `[:oban, :circuit, :open]` when the breaker is subsequently opened again.

  | event                      | measures | metadata                                              |
  | -------------------------- | -------- | ----------------------------------------------------- |
  | `[:oban, :circuit, :trip]` |          | `:kind, :reason, :message, :name, :stacktrace, :conf` |
  | `[:oban, :circuit, :open]` |          | `:name, :conf`                                        |

  Metadata

  * `:kind` — the kind of error (see the explanation above)
  * `:reason` — the error that tripped the circuit, see the error kinds breakdown above
  * `:name` — the registered name of the process that tripped a circuit, i.e. `Oban.Notifier`
  * `:message` — a formatted error message describing what went wrong
  * `:stacktrace` — exception stacktrace, when available
  * `:conf` — the config of the Oban supervisor that the producer is for

  ### Plugin Events

  All the Oban plugins emit telemetry events under the `[:oban, :plugin, *]` pattern (where `*` is
  either `:start`, `:stop`, or `:exception`). You can filter out for plugin events by looking into
  the metadata of the event and checking the value of `:plugin`. The `:plugin` key will contain the
  module name of the plugin module that emitted the event. For example, to get `Oban.Plugins.Cron`
  specific events, you can filter for telemetry events with a metadata key/value of
  `plugin: Oban.Plugins.Cron`.

  Oban emits the following telemetry event whenever a plugin executes (be sure to check the
  documentation for each plugin as each plugin can also add additional metadata specific to
  the plugin):

  * `[:oban, :plugin, :start]` — when the plugin beings performing its work
  * `[:oban, :plugin, :stop]` —  after the plugin completes its work
  * `[:oban, :plugin, :exception]` — when the plugin encounters an error

  The following chart shows which metadata you can expect for each event:

  | event        | measures       | metadata                                      |
  | ------------ | ---------------| --------------------------------------------- |
  | `:start`     | `:system_time` | `:conf, :plugin`                              |
  | `:stop`      | `:duration`    | `:conf, :plugin`                              |
  | `:exception` | `:duration`    | `:kind, :reason, :stacktrace, :conf, :plugin` |

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

        Honeybadger.notify(meta.reason, context, meta.stacktrace)
      end
    end
  end

  :telemetry.attach("oban-errors", [:oban, :job, :exception], &ErrorReporter.handle_event/4, [])
  ```

  [honey]: https://honeybadger.io
  """
  @moduledoc since: "0.4.0"

  require Logger

  @type attach_option :: {:logger_level, Logger.level()} | {:telemetry_prefix, [atom()]}

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

  Attach a logger with a specific oban prefix and level:

      :ok = Oban.Telemetry.attach_default_logger(telemetry_prefix: [:my_oban], logger_level: :debug)
  """
  @doc since: "0.4.0"
  @spec attach_default_logger(Logger.level() | [attach_option()]) ::
          :ok | {:error, :already_exists}
  def attach_default_logger(level_or_opts \\ [logger_level: :info])

  def attach_default_logger(level) when is_atom(level) do
    attach_default_logger(logger_level: level)
  end

  def attach_default_logger(opts) when is_list(opts) do
    telemetry_prefix = Keyword.get(opts, :telemetry_prefix, [:oban])
    level = Keyword.get(opts, :logger_level, :info)

    events = [
      telemetry_prefix ++ [:job, :start],
      telemetry_prefix ++ [:job, :stop],
      telemetry_prefix ++ [:job, :exception],
      telemetry_prefix ++ [:circuit, :trip],
      telemetry_prefix ++ [:circuit, :open]
    ]

    :telemetry.attach_many("oban-default-logger", events, &__MODULE__.handle_event/4, level)
  end

  @deprecated "Use the official :telemetry.span/3 instead"
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
  def handle_event([_, :job, event], measure, meta, level),
    do: handle_job_event(event, measure, meta, level)

  def handle_event([_, _, :job, event], measure, meta, level),
    do: handle_job_event(event, measure, meta, level)

  def handle_event([_, _, _, :job, event], measure, meta, level),
    do: handle_job_event(event, measure, meta, level)

  def handle_event([_, :circuit, event], _measure, meta, level),
    do: handle_circuit_event(event, meta, level)

  def handle_event([_, _, :circuit, event], _measure, meta, level),
    do: handle_circuit_event(event, meta, level)

  def handle_event([_, _, _, :circuit, event], _measure, meta, level),
    do: handle_circuit_event(event, meta, level)

  defp handle_job_event(event, measure, meta, level) do
    meta
    |> Map.take([:args, :worker, :queue])
    |> Map.merge(converted_measurements(measure))
    |> log_message("job:#{event}", level)
  end

  defp handle_circuit_event(event, meta, level) do
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
