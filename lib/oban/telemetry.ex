defmodule Oban.Telemetry do
  @moduledoc """
  Telemetry integration for event metrics, logging and error reporting.

  ## Initialization Events

  Oban emits the following telemetry event when an Oban supervisor is started:

  * `[:oban, :supervisor, :init]` - when the Oban supervisor is started this will execute

  The initialization event contains the following measurements:

  * `:system_time` - The system's time when Oban was started

  The initialization event contains the following metadata:

  * `:conf` - The configuration used for the Oban supervisor instance
  * `:pid` - The PID of the supervisor instance

  ## Job Events

  Oban emits the following telemetry events for each job:

  * `[:oban, :job, :start]` — at the point a job is fetched from the database and will execute
  * `[:oban, :job, :stop]` — after a job succeeds and the success is recorded in the database
  * `[:oban, :job, :exception]` — after a job fails and the failure is recorded in the database

  All job events share the same details about the job that was executed. In addition, failed jobs
  provide the error type, the error itself, and the stacktrace. The following chart shows which
  metadata you can expect for each event:

  | event        | measures                   | metadata                                                                |
  | ------------ | -------------------------- | ----------------------------------------------------------------------- |
  | `:start`     | `:system_time`             | `:conf`, `:job`                                                         |
  | `:stop`      | `:duration`, `:queue_time` | `:conf`, `:job`, `:state`, `:result`                                    |
  | `:exception` | `:duration`, `:queue_time` | `:conf`, `:job`, `:state`, `:kind`, `:reason`, `:result`, `:stacktrace` |

  ### Metadata

  * `:conf` — the executing Oban instance's config
  * `:job` — the executing `Oban.Job`
  * `:state` — one of `:success`, `:failure`, `:cancelled`, `:discard` or `:snoozed`
  * `:result` — the `perform/1` return value, always `nil` for an exception or crash

  For `:exception` events the metadata also includes details about what caused the failure. The
  `:kind` value is determined by how an error occurred. Here are the possible kinds:

  * `:error` — from an `{:error, error}` return value. Some Erlang functions may also throw an
    `:error` tuple, which will be reported as `:error`.
  * `:exit` — from a caught process exit
  * `:throw` — from a caught value, this doesn't necessarily mean that an error occurred and the
    error value is unpredictable

  ## Engine Events

  Oban emits telemetry span events for the following Engine operations:

  * `[:oban, :engine, :init, :start | :stop | :exception]`
  * `[:oban, :engine, :refresh, :start | :stop | :exception]`
  * `[:oban, :engine, :put_meta, :start | :stop | :exception]`

  | event        | measures       | metadata                                              |
  | ------------ | -------------- | ----------------------------------------------------- |
  | `:start`     | `:system_time` | `:conf`, `:engine`                                    |
  | `:stop`      | `:duration`    | `:conf`, `:engine`                                    |
  | `:exception` | `:duration`    | `:conf`, `:engine`, `:kind`, `:reason`, `:stacktrace` |

  Events for bulk operations also include `:jobs` for the `:stop` event:

  * `[:oban, :engine, :cancel_all_jobs, :start | :stop | :exception]`
  * `[:oban, :engine, :fetch_jobs, :start | :stop | :exception]`
  * `[:oban, :engine, :insert_all_jobs, :start | :stop | :exception]`
  * `[:oban, :engine, :prune_jobs, :start | :stop | :exception]`
  * `[:oban, :engine, :retry_all_jobs, :start | :stop | :exception]`
  * `[:oban, :engine, :stage_jobs, :start | :stop | :exception]`

  | event        | measures       | metadata                                              |
  | ------------ | -------------- | ----------------------------------------------------- |
  | `:start`     | `:system_time` | `:conf`, `:engine`                                    |
  | `:stop`      | `:duration`    | `:conf`, `:engine`, `:jobs`                                    |
  | `:exception` | `:duration`    | `:conf`, `:engine`, `:kind`, `:reason`, `:stacktrace` |

  Events for job-level Engine operations also include the `job`, with the exception of
  `:insert_job, :start`, because the `job` isn't available yet.

  * `[:oban, :engine, :cancel_job, :start | :stop | :exception]`
  * `[:oban, :engine, :complete_job, :start | :stop | :exception]`
  * `[:oban, :engine, :discard_job, :start | :stop | :exception]`
  * `[:oban, :engine, :error_job, :start | :stop | :exception]`
  * `[:oban, :engine, :insert_job, :start | :stop | :exception]`
  * `[:oban, :engine, :retry_job, :start | :stop | :exception]`
  * `[:oban, :engine, :snooze_job, :start | :stop | :exception]`

  | event        | measures       | metadata                                                      |
  | ------------ | -------------- | ------------------------------------------------------------- |
  | `:start`     | `:system_time` | `:conf`, `:engine`, `:job`                                    |
  | `:stop`      | `:duration`    | `:conf`, `:engine`, `:job`                                    |
  | `:exception` | `:duration`    | `:conf`, `:engine`, `:job`, `:kind`, `:reason`, `:stacktrace` |

  ### Metadata

  * `:conf` — the Oban supervisor's config
  * `:engine` — the module of the engine used
  * `:job` - the `Oban.Job` in question
  * `:jobs` — zero or more maps with the `queue`, `state` for each modified job
  * `:kind`, `:reason`, `:stacktrace` — see the explanation in job metadata above

  ## Notifier Events

  Oban emits a telemetry span event each time the Notifier is triggered:

  * `[:oban, :notifier, :notify, :start | :stop | :exception]`

  | event        | measures       | metadata                                                            |
  | ------------ | -------------- | ------------------------------------------------------------------- |
  | `:start`     | `:system_time` | `:conf`, `:channel`, `:payload`                                     |
  | `:stop`      | `:duration`    | `:conf`, `:channel`, `:payload`                                     |
  | `:exception` | `:duration`    | `:conf`, `:channel`, `:payload`, `:kind`, `:reason`, `:stacktrace`  |

  ### Metadata

  * `:conf` — the Oban supervisor's config
  * `:channel` — the channel on which the notification was sent
  * `:payload` - the decoded payload that was sent
  * `:kind`, `:reason`, `:stacktrace` — see the explanation in job metadata above


  Oban also emits an event when the notifier's sonar, responsible for tracking notifier
  connectivity, switches connectivity status:

  * `[:oban, :notifier, :switch]`

  | event        | measures  | metadata           |
  | ------------ | --------- | ------------------ |
  | `:switch`    |           | `:conf`, `:status` |

  ### Metadata

  * `:conf` — see the explanation in metadata above
  * `:status` — one of `:isolated`, `:solitary`, or `:clustered`, see
    `Oban.Notifier.status/1` for details

  ## Plugin Events

  All the Oban plugins emit telemetry events under the `[:oban, :plugin, *]` pattern (where `*` is
  either `:init`, `:start`, `:stop`, or `:exception`). You can filter out for plugin events by
  looking into the metadata of the event and checking the value of `:plugin`. The `:plugin` field
  is the plugin module that emitted the event. For example, to get `Oban.Plugins.Cron` specific
  events, you can filter for telemetry events with a metadata key/value of `plugin:
  Oban.Plugins.Cron`.

  Oban emits the following telemetry event whenever a plugin executes (be sure to check the
  documentation for each plugin as each plugin can also add additional metadata specific to
  the plugin):

  * `[:oban, :plugin, :init]` — when the plugin first initializes
  * `[:oban, :plugin, :start]` — when the plugin beings performing its work
  * `[:oban, :plugin, :stop]` —  after the plugin completes its work
  * `[:oban, :plugin, :exception]` — when the plugin encounters an error

  The following chart shows which metadata you can expect for each event:

  | event        | measures        | metadata                                              |
  | ------------ | --------------- | ----------------------------------------------------- |
  | `:init`      |                 | `:conf`, `:plugin`                                    |
  | `:start`     | `:system_time`  | `:conf`, `:plugin`                                    |
  | `:stop`      | `:duration`     | `:conf`, `:plugin`                                    |
  | `:exception` | `:duration`     | `:conf`, `:plugin`, `:kind`, `:reason`, `:stacktrace` |

  ## Peer Events

  Oban emits a telemetry span event each time an Oban Peer election occurs:

  * `[:oban, :peer, :election, :start | :stop | :exception]`

  | event        | measures       | metadata                                                       |
  | ------------ | -------------- | -------------------------------------------------------------- |
  | `:start`     | `:system_time` | `:conf`, `:leader`, `:peer`,                                   |
  | `:stop`      | `:duration`    | `:conf`, `:leader`, `:peer`,                                   |
  | `:exception` | `:duration`    | `:conf`, `:leader`, `:peer`, `:kind`, `:reason`, `:stacktrace` |

  ### Metadata

  * `:conf`, `:kind`, `:reason`, `:stacktrace` — see the explanation in notifier metadata above
  * `:leader` — whether the peer is the current leader
  * `:peer` — the module used for peering

  ## Stager Events

  Oban emits an event any time the Stager switches between `local` and `global` modes:

  * `[:oban, :stager, :switch]`

  | event        | measures  | metadata         |
  | ------------ | --------- | ---------------- |
  | `:switch`    |           | `:conf`, `:mode` |

  ### Metadata

  * `:conf` — see the explanation in metadata above
  * `:mode` — either `local` for polling mode or `global` in the more efficient pub-sub mode

  ## Default Logger

  A default log handler that emits structured JSON is provided, see `attach_default_logger/0` for
  usage. Otherwise, if you would prefer more control over logging or would like to instrument
  events you can write your own handler.

  Here is an example of the JSON output for the `job:stop` event:

  ```json
  {
    "args":{"action":"OK","ref":1},
    "attempt":1,
    "duration":4327295,
    "event":"job:stop",
    "id":123,
    "max_attempts":20,
    "meta":{},
    "queue":"alpha",
    "queue_time":3127905,
    "source":"oban",
    "state":"success",
    "tags":[],
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
      Logger.warning("[#\{meta.queue}] #\{meta.worker} failed in #\{duration}")
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

        Honeybadger.notify(meta.reason, metadata: context, stacktrace: meta.stacktrace)
      end
    end
  end

  :telemetry.attach("oban-errors", [:oban, :job, :exception], &ErrorReporter.handle_event/4, [])
  ```

  [honey]: https://honeybadger.io
  """
  @moduledoc since: "0.4.0"

  require Logger

  @handler_id "oban-default-logger"

  @doc """
  Attaches a default structured JSON Telemetry handler for logging.

  This function attaches a handler that outputs logs with the following fields for job events:

  * `args` — a map of the job's raw arguments
  * `attempt` — the job's execution atttempt
  * `duration` — the job's runtime duration, in the native time unit
  * `event` — `job:start`, `job:stop`, `job:exception` depending on reporting telemetry event
  * `error` — a formatted error banner, without the extended stacktrace
  * `id` — the job's id
  * `meta` — a map of the job's raw metadata
  * `queue` — the job's queue
  * `source` — always "oban"
  * `state` — the execution state, one of "success", "failure", "cancelled", "discard", or
    "snoozed"
  * `system_time` — when the job started, in microseconds
  * `tags` — the job's tags
  * `worker` — the job's worker module

  For stager events:

  * `event` — always `stager:switch`
  * `message` — information about the mode switch
  * `mode` — either `"local"` or `"global"`
  * `source` — always "oban"

  For notifier events:

  * `event` — always `notifier:switch`
  * `message` — information about the status switch
  * `source` — always "oban"
  * `status` — either `"isolated"`, `"solitary"`, or `"clustered"`

  ## Options

  * `:level` — The log level to use for logging output, defaults to `:info`
  * `:encode` — Whether to encode log output as JSON, defaults to `true`

  ## Examples

  Attach a logger at the default `:info` level with JSON encoding:

      :ok = Oban.Telemetry.attach_default_logger()

  Attach a logger at the `:debug` level:

      :ok = Oban.Telemetry.attach_default_logger(level: :debug)

  Attach a logger with JSON logging disabled:

      :ok = Oban.Telemetry.attach_default_logger(encode: false)
  """
  @doc since: "0.4.0"
  @spec attach_default_logger(Logger.level() | Keyword.t()) :: :ok | {:error, :already_exists}
  def attach_default_logger(opts \\ [encode: true, level: :info])

  def attach_default_logger(level) when is_atom(level) do
    attach_default_logger(level: level)
  end

  def attach_default_logger(opts) when is_list(opts) do
    events = [
      [:oban, :job, :start],
      [:oban, :job, :stop],
      [:oban, :job, :exception],
      [:oban, :notifier, :switch],
      [:oban, :stager, :switch]
    ]

    opts =
      opts
      |> Keyword.put_new(:encode, true)
      |> Keyword.put_new(:level, :info)

    :telemetry.attach_many(@handler_id, events, &__MODULE__.handle_event/4, opts)
  end

  @doc """
  Undoes `Oban.Telemetry.attach_default_logger/1` by detaching the attached logger.

  ## Examples

  Detach a previously attached logger:

      :ok = Oban.Telemetry.attach_default_logger()
      :ok = Oban.Telemetry.detach_default_logger()

  Attempt to detach when a logger wasn't attached:

      {:error, :not_found} = Oban.Telemetry.detach_default_logger()
  """
  @doc since: "2.15.0"
  @spec detach_default_logger() :: :ok | {:error, :not_found}
  def detach_default_logger do
    :telemetry.detach(@handler_id)
  end

  @doc false
  @spec handle_event([atom()], map(), map(), Keyword.t()) :: :ok
  def handle_event([:oban, :job, event], measure, meta, opts) do
    log(opts, fn ->
      details = Map.take(meta.job, ~w(attempt args id max_attempts meta queue tags worker)a)

      extra =
        case event do
          :start ->
            %{event: "job:start", system_time: measure.system_time}

          :stop ->
            %{
              duration: convert(measure.duration),
              event: "job:stop",
              queue_time: convert(measure.queue_time),
              state: meta.state
            }

          :exception ->
            %{
              error: Exception.format_banner(meta.kind, meta.reason, meta.stacktrace),
              event: "job:exception",
              duration: convert(measure.duration),
              queue_time: convert(measure.queue_time),
              state: meta.state
            }
        end

      Map.merge(details, extra)
    end)
  end

  def handle_event([:oban, :notifier, :switch], _measure, %{status: status}, opts) do
    log(opts, fn ->
      case status do
        :isolated ->
          %{
            event: "notifier:switch",
            status: status,
            message: "notifier can't receive messages from any nodes, functionality degraded"
          }

        :solitary ->
          %{
            event: "notifier:switch",
            status: status,
            message:
              "notifier only receiving messages from its own node, functionality may be degraded"
          }

        :clustered ->
          %{
            event: "notifier:switch",
            status: status,
            message: "notifier is receiving messages from other nodes"
          }
      end
    end)
  end

  def handle_event([:oban, :stager, :switch], _measure, %{mode: mode}, opts) do
    log(opts, fn ->
      case mode do
        :local ->
          %{
            event: "stager:switch",
            mode: mode,
            message:
              "job staging switched to local mode. local mode polls for jobs for every queue; " <>
                "restore global mode with a functional notifier"
          }

        :global ->
          %{
            event: "stager:switch",
            mode: mode,
            message: "job staging switched back to global mode"
          }
      end
    end)
  end

  defp log(opts, fun) do
    level = Keyword.fetch!(opts, :level)

    Logger.log(level, fn ->
      output = Map.put(fun.(), :source, "oban")

      if Keyword.fetch!(opts, :encode) do
        Jason.encode_to_iodata!(output)
      else
        output
      end
    end)
  end

  defp convert(value), do: System.convert_time_unit(value, :native, :microsecond)
end
