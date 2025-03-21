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

  | event        | measures                                             | metadata                                                                |
  | ------------ | ---------------------------------------------------- | ----------------------------------------------------------------------- |
  | `:start`     | `:system_time`                                       | `:conf`, `:job`                                                         |
  | `:stop`      | `:duration`, `:memory`, `:queue_time`, `:reductions` | `:conf`, `:job`, `:state`, `:result`                                    |
  | `:exception` | `:duration`, `:memory`, `:queue_time`, `:reductions` | `:conf`, `:job`, `:state`, `:kind`, `:reason`, `:result`, `:stacktrace` |

  #### Metadata

  * `:conf` — the executing Oban instance's config
  * `:job` — the executing `Oban.Job`
  * `:result` — the `perform/1` return value, always `nil` for an exception or crash
  * `:state` — one of `:success`, `:failure`, `:cancelled`, `:discard` or `:snoozed`

  For `:exception` events the metadata also includes details about what caused the failure.

  * `:kind` — describes how an error occurred. Here are the possible kinds:
    - `:error` — from an `{:error, error}` return value. Some Erlang functions may also throw an
      `:error` tuple, which will be reported as `:error`.
    - `:exit` — from a caught process exit
    - `:throw` — from a caught value, this doesn't necessarily mean that an error occurred and the
      error value is unpredictable

  * `:reason` — a raised exception, wrapped crash, or wrapped error that caused the job to fail.
    Raised exceptions are passes as is, crashes are wrapped in an `Oban.CrashError`, timeouts in
    `Oban.TimeoutError`, and all other errors are normalized into an `Oban.PerformError`.

  * `:stacktrace` — the `t:Exception.stacktrace/0` for crashes or raised exceptions. Failures from
    manual error returns won't contain any application code entries and may have an empty
    stacktrace.

  ## Engine Events

  Oban emits telemetry span events for the following Engine operations:

  * `[:oban, :engine, :init, :start | :stop | :exception]`
  * `[:oban, :engine, :refresh, :start | :stop | :exception]`
  * `[:oban, :engine, :put_meta, :start | :stop | :exception]`
  * `[:oban, :engine, :check_available, :start | :stop | :exception]`

  | event        | measures       | metadata                                              |
  | ------------ | -------------- | ----------------------------------------------------- |
  | `:start`     | `:system_time` | `:conf`, `:engine`                                    |
  | `:stop`      | `:duration`    | `:conf`, `:engine`                                    |
  | `:exception` | `:duration`    | `:conf`, `:engine`, `:kind`, `:reason`, `:stacktrace` |

  Events for bulk operations also include `:jobs` for the `:stop` event:

  * `[:oban, :engine, :cancel_all_jobs, :start | :stop | :exception]`
  * `[:oban, :engine, :delete_all_jobs, :start | :stop | :exception]`
  * `[:oban, :engine, :fetch_jobs, :start | :stop | :exception]`
  * `[:oban, :engine, :insert_all_jobs, :start | :stop | :exception]`
  * `[:oban, :engine, :prune_jobs, :start | :stop | :exception]`
  * `[:oban, :engine, :rescue_jobs, :start | :stop | :exception]`
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
  * `[:oban, :engine, :delete_job, :start | :stop | :exception]`
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

  #### Metadata

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

  #### Metadata

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

  #### Metadata

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
  | `:stop`      | `:duration`    | `:conf`, `:leader`, `:peer`, `:was_leader`                    |
  | `:exception` | `:duration`    | `:conf`, `:leader`, `:peer`, `:kind`, `:reason`, `:stacktrace` |

  #### Metadata

  * `:conf`, `:kind`, `:reason`, `:stacktrace` — see the explanation in notifier metadata above
  * `:leader` — whether the peer is the current leader
  * `:was_leader` — whether the peer was the leader before the election occurred
  * `:peer` — the module used for peering

  ## Queue Events

  Oban emits an event when a queue shuts down cleanly, e.g. without being brutally killed. Event
  emission isn't guaranteed because it is emitted as part of a `terminate/1` callback.

  * `[:oban, :queue, :shutdown]`

  | event       | measures   | metadata                       |
  | ----------- | -----------| ------------------------------ |
  | `:shutdown` | `:elapsed` | `:conf`, `:orphaned`, `:queue` |

  #### Metadata

  * `:conf` — see the explanation in metadata above
  * `:orphaned` — a list of job id's left in an `executing` state because they couldn't finish
  * `:queue` — the stringified queue name

  ## Stager Events

  Oban emits an event any time the Stager switches between `local` and `global` modes:

  * `[:oban, :stager, :switch]`

  | event        | measures  | metadata         |
  | ------------ | --------- | ---------------- |
  | `:switch`    |           | `:conf`, `:mode` |

  #### Metadata

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

  alias Oban.JSON

  require Logger

  @typedoc """
  The types of telemetry events, essentially the second element of each event list. For example,
  in the event `[:oban, :job, :start]`, the "type" is `:job`.
  """
  @type event_types :: :job | :notifier | :plugin | :peer | :queue | :stager

  @typedoc """
  Available logging options.
  """
  @type logger_opts :: [encode: boolean(), events: :all | [event_types()], level: Logger.level()]

  @doc """
  The unique id used to attach telemetry logging.

  This is the constant `"oban-default-logger"` and exposed for testing purposes.
  """
  @doc since: "1.19.0"
  def default_handler_id, do: "oban-default-logger"

  @doc """
  Attaches a default structured JSON Telemetry handler for logging.

  This function attaches a handler that outputs logs with `message` and `source` fields, along
  with some event specific fields.

  #### Job Events

  * `args` — a map of the job's raw arguments
  * `attempt` — the job's execution atttempt
  * `duration` — the job's runtime duration in microseconds
  * `event` — `job:start`, `job:stop`, `job:exception` depending on reporting telemetry event
  * `error` — a formatted error banner, without the extended stacktrace
  * `id` — the job's id
  * `meta` — a map of the job's raw metadata
  * `queue` — the job's queue
  * `state` — the execution state, one of "success", "failure", "cancelled", "discard", or
    "snoozed"
  * `system_time` — when the job started, in microseconds
  * `tags` — the job's tags
  * `worker` — the job's worker module

  #### Queue Events

  * `elapsed` — the amount of time the queue waited for shutdown, in milliseconds
  * `event` — always `queue:shutdown`
  * `orphaned` — a list of any job id's left in an `executing` state
  * `queue` — the queue name

  #### Notifier Events

  * `event` — always `notifier:switch`
  * `message` — information about the status switch
  * `status` — either `"isolated"`, `"solitary"`, or `"clustered"`

  #### Peer Events

  * `event` — always `peer:election`
  * `leader` — boolean indicating whether the peer is the leader
  * `message` — information about the peers role in an election
  * `node` — the name of the node that changed leadership
  * `was_leader` — boolean indicating whether the peer was leader before the election

  #### Plugin Events

  * `event` — `plugin:stop` or `plugin:exception`
  * `plugin` — the plugin module
  * `duration` — the runtime duration in microseconds

  Other values may be included depending on the plugin.

  #### Stager Events

  * `event` — always `stager:switch`
  * `message` — information about the mode switch
  * `mode` — either `"local"` or `"global"`

  ## Options

  * `:encode` — Whether to encode log output as JSON rather than using structured logging,
    defaults to `true`

  * `:events` — Which event categories to log, where the categories include `:job`, `:notifier`,
    `:plugin`, `:peer`, `:queue`, `:stager`, or `:all`. Defaults to `:all`.

  * `:level` — The log level to use for logging output, defaults to `:info`

  ## Examples

  Attach a logger at the default `:info` level with JSON encoding:

      Oban.Telemetry.attach_default_logger()

  Attach a logger at the `:debug` level:

      Oban.Telemetry.attach_default_logger(level: :debug)

  Attach a logger with JSON logging disabled:

      Oban.Telemetry.attach_default_logger(encode: false)

  Explicitly attach a logger for all supported events:

      Oban.Telemetry.attach_default_logger(events: :all)

  Attach a logger with only `:notifier`, `:peer`, and `:stager` events logged:

      Oban.Telemetry.attach_default_logger(events: ~w(notifier peer stager)a)
  """
  @doc since: "0.4.0"
  @spec attach_default_logger(Logger.level() | logger_opts()) :: :ok | {:error, :already_exists}
  def attach_default_logger(opts \\ [])

  def attach_default_logger(level) when is_atom(level) do
    attach_default_logger(level: level)
  end

  def attach_default_logger(opts) when is_list(opts) do
    opts =
      opts
      |> Keyword.put_new(:encode, true)
      |> Keyword.put_new(:events, :all)
      |> Keyword.put_new(:level, :info)

    filter = opts[:events]

    events =
      for [category | rest] <- [
            ~w(job start)a,
            ~w(job stop)a,
            ~w(job exception)a,
            ~w(notifier switch)a,
            ~w(peer election stop)a,
            ~w(plugin exception)a,
            ~w(plugin stop)a,
            ~w(queue shutdown)a,
            ~w(stager switch)a
          ],
          filter == :all or category in filter,
          do: [:oban, category | rest]

    :telemetry.attach_many(default_handler_id(), events, &__MODULE__.handle_event/4, opts)
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
    :telemetry.detach(default_handler_id())
  end

  @doc false
  @spec handle_event([atom()], map(), map(), Keyword.t()) :: term()
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
            connectivity_status: status,
            message: "notifier can't receive messages from any nodes, functionality degraded"
          }

        :solitary ->
          %{
            event: "notifier:switch",
            connectivity_status: status,
            message:
              "notifier only receiving messages from its own node, functionality may be degraded"
          }

        :clustered ->
          %{
            event: "notifier:switch",
            connectivity_status: status,
            message: "notifier is receiving messages from other nodes"
          }
      end
    end)
  end

  def handle_event([:oban, :peer, :election, :stop], _measure, meta, opts) do
    %{leader: leader, was_leader: was_leader} = meta

    message =
      cond do
        leader and not was_leader -> "peer became leader"
        not leader and was_leader -> "peer is no longer leader"
        true -> :ignore
      end

    if message != :ignore do
      log(opts, fn ->
        %{
          event: "peer:election",
          leader: leader,
          message: message,
          node: meta.conf.node,
          was_leader: was_leader
        }
      end)
    else
      :ok
    end
  end

  def handle_event([:oban, :plugin, :exception], measure, meta, opts) do
    log(opts, fn ->
      error =
        case meta do
          %{kind: kind, reason: reason, stacktrace: stacktrace} ->
            Exception.format_banner(kind, reason, stacktrace)

          %{error: error} ->
            Exception.format_banner(:error, error)
        end

      %{
        duration: convert(measure.duration),
        error: error,
        event: "plugin:exception",
        plugin: inspect(meta.plugin)
      }
    end)
  end

  def handle_event([:oban, :plugin, :stop], measure, meta, opts) do
    %{conf: conf, plugin: plugin} = meta

    if function_exported?(plugin, :format_logger_output, 2) do
      log(opts, fn ->
        formatted = plugin.format_logger_output(conf, meta)

        %{event: "plugin:stop", plugin: inspect(plugin)}
        |> Map.put(:duration, convert(measure.duration))
        |> Map.merge(formatted)
      end)
    end
  end

  def handle_event([:oban, :queue, :shutdown], measure, %{orphaned: [_ | _]} = meta, opts) do
    log(opts, fn ->
      %{
        elapsed: measure.elapsed,
        event: "queue:shutdown",
        orphaned: meta.orphaned,
        queue: meta.queue,
        message: "jobs were orphaned because they didn't finish executing in the allotted time"
      }
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

  def handle_event(_event, _measure, _meta, _opts), do: :ok

  defp log(opts, fun) do
    level = Keyword.fetch!(opts, :level)

    Logger.log(level, fn ->
      output = Map.put(fun.(), :source, "oban")

      if Keyword.fetch!(opts, :encode) do
        JSON.encode_to_iodata!(output)
      else
        output
      end
    end)
  end

  defp convert(value), do: System.convert_time_unit(value, :native, :microsecond)
end
