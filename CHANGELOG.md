# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](http://semver.org/spec/v2.0.0.html).

## Unreleased

## [2.3.3] — 2020-11-10

- [Oban.Migration] Conditionally skip altering `oban_job_state` if the
  `cancelled` state is already present. This allows for a smoother upgrade path
  for users running PG < 12. See the notes for v2.3.0 for more details.

## [2.3.2] — 2020-11-06

- [Oban.Migration] Restore indexes possibly removed by changing
  `oban_job_state`. This only applies to PG older than version 12.

- [Oban.Plugins.Pruner] Prune `cancelled` jobs along with `completed` or
  `discarded`.

## [2.3.1] — 2020-11-06

- [Oban.Migration] Conditionally alter `oban_job_state` if the PG version is 12
  or greater. This is **vastly** faster than the renaming, adding and dropping
  required for older PG versions.

## [2.3.0] — 2020-11-06

**Migration Required (V9)**

Migration V9 brings the new `cancelled` state, a `cancelled_at` column, and job
`meta`.

Older versions of PostgreSQL, prior to version 12, don't allow altering an enum
within a transaction. If you're running an older version and want to prevent a
table rewrite you can add the new cancelled at state before running the V9
migration.

Create a migration with `@disable_ddl_transaction true` declared and run the
command `ALTER TYPE oban_job_state ADD VALUE IF NOT EXISTS 'cancelled'`. The V9
migration will see that the cancelled value exists and won't attempt to modify
the enum.

After you've sorted adding the `cancelled` state (or ignored the issue, because
you're either running PG >= 12 or don't have many jobs retained), generate a new
migration:

```bash
mix ecto.gen.migration upgrade_oban_jobs_to_v9
```

Next, call `Oban.Migrations` in the generated migration:

```elixir
defmodule MyApp.Repo.Migrations.UpdateObanJobsToV9 do
  use Ecto.Migration

  defdelegate up, to: Oban.Migrations
  defdelegate down, to: Oban.Migrations
end
```

Oban will manage upgrading to V9 regardless of the version your application is
currently using, and it will roll back a single version.

### Added

- [Oban.Job] Add new `meta` field for storing arbitrary job data that isn't
  appropriate as `args`.

- [Oban.Job] Introduce a `cancelled` state, along with a new `cancelled_at`
  timestamp field. Cancelling a job via `Oban.cancel_job` (or via Oban Web) now
  marks the job as `cancelled` rather than `discarded`.

- [Oban.Worker] Add `from_string/1` for improved worker module resolution.

- [Oban.Telemetry] Pass the full `job` schema in telemetry metadata, not only
  select fields. Individual fields such as `args`, `worker`, etc. are still
  passed for backward compatibility. However, their use is deprecated and they
  are no longer documented.

### Fixed

- [Oban.Notifier] Fix resolution of `Oban.Notifier` child process in `Oban.Notifier.listen/2`.

- [Oban.Queue.Producer] Fix cancelling jobs without a supervised process. In
  some circumstances, namely a hot code upgrade, the job's process could
  terminate without the producer tracking it and leave the job un-killable.

- [Oban] Only convert invalid changesets into `ChangesetError` from `insert!`.
  This prevents unexpected errors when `insert!` is called within a transaction
  after the transaction has rolled back.

## [2.2.0] — 2020-10-12

### Added

- [Oban] Replace local dynamically composed names with a registry. This
  dramatically simplifies locating nested children, avoids unnecessary atom
  creation at runtime and improves the performance of config lookups.

- [Oban.Repo] The new `Oban.Repo` module wraps interactions with underlying Ecto
  repos. This ensures consistent prefix and log level handling, while also
  adding full dynamic repo support.

  The `Oban.Repo` wrapper should be used when authoring plugins.

- [Oban.Job] Augment the unique keys option with `replace_args`, which allows
  enqueuing a unique job and replacing the args subsequently. For example, given
  a job with these args:

    ```elixir
    %{some_value: 1, id: 123}
    ```

  Attempting to insert a new job:

    ```elixir
    %{some_value: 2, id: 123}
    |> MyJob.new(schedule_in: 10, replace_args: true unique: [keys: [:id]])
    |> Oban.insert()
    ```

  Will result in a single job with the args:

    ```elixir
    %{some_value: 2, id: 123}
    ```

- [Oban] Add `Oban.check_queue/1,2` for runtime introspection of a queue's
  state. It displays a compactly formatted breakdown of the queue's
  configuration, a list of running jobs, and static identity information.

- [Oban] Add `Oban.retry_job/1,2`, used to manually retry a `discarded` or
  `retryable` job.

- [Oban.Telemetry] Include `tags` as part of the metadata for job events.

### Changed

- [Oban.Worker] The default backoff algorithm now includes a small amount of
  jitter. The jitter helps prevent jobs that fail simultaneously from repeatedly
  retrying together.

### Fixed

- [Oban.Job] Don't include `discarded` state by default when accounting for
  uniqueness.

- [Oban.Cron] Fully support weekeday ranges in crontab expressions. Previously,
  given a weekday range like `MON-WED` the parser would only retain the `MON`.

## [2.1.0] — 2020-08-21

### Fixed

- [Oban.Testing] Modify the behaviour checking in `perform_job/3` so that it
  considers all behaviours.

- [Oban.Plugins.Pruner] Use distinct names when running multiple Oban instances
  in the same application.

### Added

- [Oban] In addition to the standard queue-name / limit keyword syntax it is now
  possible to define per-queue options such as `:poll_interval`,
  `:dispatch_cooldown`, `:paused`, and even override the `:producer` module.

- [Oban] Cancelling a running job now records an error on the job if it was
  _running_ at the time it was cancelled.

- [Oban.Job] Allow using `:discarded` as a unique state and expose all possible
  states through `Oban.Job.states/0`.

- [Oban.Worker] Allow returning `{:discard, reason}` from `perform/1`, where the
  reason is recorded in the job's errors array. If no reason is provided then a
  default of "None" is used. All discarded jobs will have an error now, whether
  discarded manually or automatically.

- [Oban.Job] Add support for uniqueness across sub-args with the `:keys`
  attribute. This makes it possible to only use a few values from a job to
  determine uniqueness. For example, a job that includes a lot of metadata but
  must be considered unique based on a `:url` field can specify `keys: [:url]`.

### Changed

- [Oban.Worker] Wrap `{:error, reason}` and `{:discard, reason}` in a proper
  `Oban.PerformError` exception with a customized message. This ensures that the
  `:error` value passed to telemetry handlers is an exception and not a raw
  term.

- [Oban.Worker] Wrap job timeouts in `Oban.TimeoutError` with a customized
  message indicating the worker and timeout value. This replaces the raw
  `:timeout` atom that was reported before.

- [Oban.Worker] Wrap caught exits and throws in `Oban.CrashError` with a
  formatted message. This means the `:error` value passed to telemetry is
  _always_ a proper exception and easier to report.

- [Oban.Worker] Stop reporting internal stacktraces for timeouts, discards or
  error tuples. The stacktrace was useless and potentially misleading as it
  appeared that the error originated from Oban rather than the worker module.

## [2.0.0] — 2020-07-10

No changes from [2.0.0-rc.3][].

## [2.0.0-rc.3] — 2020-07-01

### Fixed

- [Oban.Crontab.Cron] Do not raise an `ArgumentError` exception when the
  crontab configuration includes a step of 1, which is a valid step value.

- [Oban.Telemetry] Correctly record `duration` and `queue_time` using native
  time units, but log them using microseconds. Previously they used a mixture of
  native and microseconds, which yielded inconsistent values.

### Added

- [Oban.Telemetry] Include job `queue_time` in the default logger output.

### Changed

- [Oban.Plugins.Pruner] The `FixedPruner` is renamed to `Pruner` and allows
  users to configure the `max_age` value. This partially reverses the breaking
  change imposed by the move from `prune` to the `FixedPruner` plugin, though
  there isn't any support for `max_len` or dynamic pruning.

## [2.0.0-rc.2] — 2020-06-23

### Breaking Changes

- [Oban] The interface for `pause_queue/2`, `resume_queue/2` and `scale_queue/3`
  now matches the recently changed `start_queue/2` and `stop_queue/2`. All queue
  manipulation functions now have a consistent interface, including the ability
  to work in `:local_only` mode. See the notes around `start_queue/2` and
  `stop_queue/2` in [2.0.0-rc.1][] for help upgrading.

- [Oban] Replace `drain_queue/3` with `drain_queue/2`, which now has an
  interface consistent with the other `*_queue/2` operations.

  Where you previously called `drain_queue/2,3` like this:

    ```elixir
    Oban.drain_queue(:myqueue, with_safety: false)
    ```

  You'll now it with options, like this:

    ```elixir
    Oban.drain_queue(queue: :myqueue, with_safety: false)
    ```

### Fixed

- [Oban.Breaker] Prevent connection bomb when the Notifier experiences repeated
  disconnections.

- [Oban.Queue.Executor] Fix error reporting when a worker fails to resolve.

- [Oban.Telemetry] Stop logging the `:error` value for circuit trip events. The
  error is a struct that isn't JSON encodable. We include the normalized
  Postgrex / DBConnection message already, so the error is redundant.

### Added

- [Oban.Crontab] Add `@reboot` special case to crontab scheduling

- [Oban.Telemetry] Add new `:producer` events for descheduling and dispatching
  jobs from queue producers.

### Removed

- [Oban] Removed `Oban.kill_job/2`, which wasn't as flexible as
  `Oban.cancel_job/2`. Use `Oban.cancel_job/2` instead to safely discard
  scheduled jobs or killing executing jobs.

## [2.0.0-rc.1] — 2020-06-12

### Breaking Changes

- [Oban.Config] The `:verbose` setting is renamed to `:log`. The setting started
  off as a simple boolean, but it has morphed to align with the log values
  accepted by calls to `Ecto.Repo`.

  To migrate, replace any `:verbose` declarations:

    ```elixir
    config :my_app, Oban,
      verbose: false,
      ...
    ```

  With use of `:log` instead:

    ```elixir
    config :my_app, Oban,
      log: false,
      ...
    ```

- [Oban] The interface for `start_queue/3` is replaced with `start_queue/2` and
  `stop_queue/2` no longer accepts a queue name as the second argument. Instead,
  both functions now accept a keyword list of options. This enables the new
  `local_only` flag, which allows you to dynamically start and stop queues only
  for the local node.

  Where you previously called `start_queue/2,3` or `stop_queue/2` like this:

    ```elixir
    :ok = Oban.start_queue(:myqueue, 10)
    :ok = Oban.stop_queue(:myqueue)
    ```

  You'll now call them with options, like this:

    ```elixir
    :ok = Oban.start_queue(queue: :myqueue, limit: 10)
    :ok = Oban.stop_queue(queue: :myqueue)
    ```

  Or, to only control the queue locally:

    ```elixir
    :ok = Oban.start_queue(queue: :myqueue, limit: 10, local_only: true)
    :ok = Oban.stop_queue(queue: :myqueue, local_only: true)
    ```

## [2.0.0-rc.0] — 2020-06-03

### Breaking Changes

- [Oban.Worker] The `perform/2` callback is replaced with `perform/1`, where the
  only argument is an `Oban.Job` struct. This unifies the interface for all
  `Oban.Worker` callbacks and helps to eliminate confusion around pattern
  matching on arguments.

  To migrate change all worker definitions from accepting an `args` map and a
  `job` struct:

    ```elixir
    def perform(%{"id" => id}, _job), do: IO.inspect(id)
    ```

  To accept a single `job` struct and match on the `args` key directly:

    ```elixir
    def perform(%Job{args: %{"id" => id}}), do: IO.inspect(id)
    ```

- [Oban.Worker] The `backoff/1` callback now expects a job struct instead of an
  integer. That allows applications to finely control backoff based on more than
  just the current attempt number. Use of `backoff/1` with an integer is
  no longer supported.

  To migrate change any worker definitions that used a raw `attempt` like this:

    ```elixir
    def backoff(attempt), do: attempt * 60
    ```

  To match on a job struct instead, like this:

    ```elixir
    def backoff(%Job{attempt: attempt}), do: attempt * 60
    ```

- [Oban.Telemetry] The format for telemetry events has changed to match the new
  telemetry `span` convention. This listing maps the old event to the new one:

    * `[:oban, :started]` -> `[:oban, :job, :start]`
    * `[:oban, :success]` -> `[:oban, :job, :stop]`
    * `[:oban, :failure]` -> `[:oban, :job, :exception]`
    * `[:oban, :trip_circuit]` -> `[:oban, :circuit, :trip]`
    * `[:oban, :open_circuit]` -> `[:oban, :circuit, :open]`

  In addition, for exceptions the stacktrace meta key has changed from `:stack`
  to the standardized `:stacktrace`.

- [Oban.Prune] Configurable pruning is no longer available. Instead, pruning is
  handled by the new plugin system. A fixed period pruning module is enabled as
  a default plugin. The plugin always retains "prunable" (discarded or complete)
  jobs for 60 seconds.

  Remove any `:prune`, `:prune_interval` or `prune_limit` settings from your
  config. To disable the pruning plugin in test mode set `plugins: false`
  instead.

- [Oban.Beat] Pulse tracking and periodic job rescue are no longer available.
  Pulse tracking and rescuing will be handled by an external plugin. This is
  primarily an implementation detail, but it means that jobs may be left in the
  `executing` state after a crash or forced shutdown.

  Remove any `:beats_maxage`, `:rescue_after` or `:rescue_interval` settings
  from your config.

### Fixed

- [Oban.Scheduler] Ensure isolation between transaction locks in different
  prefixes. A node with multiple prefix-isolated instances (i.e. "public" and
  "private") would always attempt to schedule cron jobs at the same moment. The
  first scheduler would acquire a lock and block out the second, preventing the
  second scheduler from ever scheduling jobs.

- [Oban.Query] Correctly prefix unprepared unique queries. Unique queries always
  targeted the "public" prefix, which either caused incorrect results when there
  were both "public" and an alternate prefix. In situations where there wasn't
  a public `oban_jobs` table at all it would cause cryptic transaction errors.

- [Oban.Query] Wrap all job fetching in an explicit transaction to enforce `FOR
  UPDATE SKIP LOCKED` semantics. Prior to this it was possible to run the same
  job at the same time on multiple nodes.

- [Oban.Crontab] Fix weekday matching for Sunday, which is represented as `0` in
  crontabs.

### Added

- [Oban] Bubble up errors and exits when draining queues by passing
  `with_safety: false` as an option to `Oban.drain_queue/3`.

- [Oban] Add `Oban.cancel_job/2` for safely discarding scheduled jobs or killing
  executing jobs. This deprecates `kill_job/2`, which isn't as flexible.

- [Oban.Worker] Support returning `{:snooze, seconds}` from `perform/1` to
  re-schedule a job some number of seconds in the future. This is useful for
  recycling jobs that aren't ready to run yet, e.g. because of rate limiting.

- [Oban.Worker] Support returning `:discard` from `perform/1` to immediately
  discard a job. This is useful when a job encounters an error that won't
  resolve with time, e.g. invalid arguments or a missing record.

- [Oban.Job] Introduce a virtual `unsaved_error` field, which is populated with
  an error map after failed execution. The `unsaved_error` field is set before
  any calls to the worker's `backoff/1` callback, allowing workers to calculate
  a custom backoff depending on the error that failed the job.

- [Oban.Worker] Add `:infinity` option for unique period.

- [Oban.Telemetry] Add `span/3` for reporting normalized `:start`, `:stop` and
  `:exception` events with timing information.

- [Oban.Telemetry] Include the configured `prefix` in all event metadata. This
  makes it possible to identify which schema prefix a job ran with, which is
  useful for differentiating errors in a multi-tenant system.

- [Oban.Telemetry] Include `queue_time` as a measurement with `stop` and
  `exception` events. This is a measurement in milliseconds of the amount of
  time between when a job was scheduled to run and when it was last attempted.

- [Oban.Testing] Add `perform_job/2,3` helper to automate validating,
  normalizing and performing jobs while unit testing. This is now the preferred
  way to unit test workers.

  To update your tests replace any calls to `perform/1,2` with the new
  `Oban.Testing.perform_job/2,3` helper:

  ```elixir
  defmodule MyApp.WorkerTest do
    use MyApp.DataCase, async: true

    use Oban.Testing, repo: MyApp.Repo

    alias MyApp.Worker

    test "doing business in my worker" do
      assert :ok = perform_job(Worker, %{id: 1})
    end
  end
  ```

  The `perform_job/2,3` helper will verify the worker, the arguments and any
  provided options. It will then verify that your worker returns a valid result
  and return the value for you to assert on.

- [Oban.Crontab] Add support for non-standard expressions such as `@daily`,
  `@hourly`, `@midnight`, etc.

- [Oban.Crontab] Add support for using step values in conjunction with ranges,
  enabling expressions like `10-30/2`, `15-45/3`, etc.

### Changed

- [Oban.Notifier] Make the module public and clean up the primary function
  interfaces. Listening for and delivering notifications is simplified and no
  longer requires macros for pattern matching.

  Notifier dispatching performance is slightly improved as well. It is now a
  no-op if no processes are listening to a notification's channel.

- [Oban.Query] The `completed_at` timestamp is no longer set for failed jobs,
  whether they are put in the `discarded` or `retryable` state. However, the
  information is still available and is recorded in the `errors` array as the
  `at` value with the error for that attempt.

  This corrects a long standing inconsistency between discarding a job manually
  or automatically when it exhausts retries.

- [Oban.Producer] Stop dispatching jobs immediately on queue startup. Instead,
  only dispatch on the first poll. This makes it possible to send the producer
  a message or allow sandboxed connection access before the initial dispatch.

- [Oban.Worker] Limit default backoff calculations to 20 attempts, or roughly 24
  days. The change addresses an issue with snoozing, which can increase a job's
  attempts into the hundreds or thousands. In this situation the algorithm
  calculates the backoff using a ratio of attempts to max attempts, but is still
  limited to roughly 24 days.

## [1.2.0] — 2020-03-05

### Fixed

- [Oban] Handle the `:shutdown` message when a job is killed purposefully.
  Previously the message was ignored, which caused the producer to keep a
  reference to the discarded job and prevented dispatching additional jobs.

### Added

- [Oban.Testing] Add `assert_enqueued/2` and `refute_enqueued/2` to allow
  asserting with a timeout, like `assert_received`.

- [Oban.Telemetry] Add `[:oban, :started]` event to report the system time as
  `start_time` when jobs start. This enables span tracking for jobs, improving
  integration with monitoring tools like NewRelic.

## [1.1.0] — 2020-02-17

### Fixed

- [Oban.Crontab] Allow any number of spaces and/or tabs in cron expressions.

- [Oban.Pruner] Prevent deadlocks while pruning by ensuring that only a single
  node can prune at any given time.

- [Oban.Queue.Executor] Improve handling of nested/linked process failures.
  Previously if a job spawned a process that crashed (i.e. through Task.async)
  then the job was left stuck in an executing state.

### Added

- [Oban.Worker] Add `timeout/1` callback for limiting how long a job may
  execute. The default value is `:infinity`, which allows a job to run
  indefinitely and mirrors the previous behavior.

- [Oban.Telemetry] Add `:error` and `:stack` to `trip_circuit` event metadata.

- [Oban.Queue.Executor] Retry success/failure database updates after a job
  finishes.

  On occasion something may happen to the database connection and updating a
  job's state would fail. Now we retry writing with a linear backoff to prevent
  the job from getting stuck in an executing state.

### Changed

- [Oban.Worker] Tighten the spec for `perform/2`. Now workers are expected to
  return only `:ok`, `{:ok, result}` or `{:error, reason}`. A warning is logged
  if any other value is returned—for high throughput systems this may cause
  performance issues and you should update your worker's return values.

  Returning a success tuple is supported for testing purposes and backward
  compatibility, while returning `:ok` on success if preferred.

## [1.0.0] — 2020-01-29

No changes from [1.0.0-rc.2][].

## [1.0.0-rc.2] — 2020-01-22

### Fixed

- [Oban.Migration] Separate adding and modifying new columns in the V8
  migration. The columns can't be modified without a `flush`.

### Changed

- [Oban.Testing] Accept a custom prefix when making test assertions.

## [1.0.0-rc.1] — 2020-01-21

**Migration Required (V8)**

This is the first required migration since 0.8.0, released in 09/2019. It brings
with it a new column, `discarded_at`, a streamlined notifications trigger, job
prioritiy and job tags.

Upgrading only requires running the new migration.

First, generate a new migration:

```bash
mix ecto.gen.migration upgrade_oban_jobs_to_v8
```

Next, call `Oban.Migrations` in the generated migration:

```elixir
defmodule MyApp.Repo.Migrations.UpdateObanJobsToV8 do
  use Ecto.Migration

  def up, do: Oban.Migrations.up(version: 8)
  def down, do: Oban.Migrations.down()
end
```

Oban will manage upgrading to V8 regardless of the version your application is
currently using, and it will roll back a single version.

### Added

- [Oban] Add `timezone` support for scheduling cronjobs using timezones other
  than "Etc/UTC". Using a custom timezone requires a timezone database such as
  tzdata.

- [Oban] Add `dispatch_cooldown` option to configure the minimum time between
  a producer fetching more jobs to execute.

- [Oban] Add `beats_maxage` option to configure how long heartbeat rows are
  retained in the `oban_beats` table. Each queue generates one row per second,
  so rows may accumulate quickly. The default value is now five minutes, down
  from one hour previously.

- [Oban.Job] Add `discarded_at` timestamp to help identify jobs that were
  discarded and not completed. The timestamp is added by the V8 migration and it
  is also included in the original `create table` from V1 as a minor space
  saving optimization (packing datetime columns together because they use a
  predictable 4bytes of space).

- [Oban.Job] Add numerical `priority` value to control the order of execution
  for jobs within a queue. The `priority` can be set between 0 and 3, with 0
  being the default and the highest priority.

- [Oban.Job] Add `tags` field for arbitrarily organizing associated tags. Tags
  are a list of strings stored as an `array` in the database, making them easy
  to search and filter by.

### Changed

- [Oban] Change the default `prune` value from `:disabled` to `{:maxlen,
  1_000}`. Many people don't change the default until they realize that a lot of
  jobs are lingering in the database. It is rare that anybody would want to keep
  all of their jobs forever, so a conservative default is better than
  `:disabled`.

- [Oban] Change `oban_beats` retention from one hour to five minutes. The value
  is now configurable, with a default of `300s`. The lower bound is `60s`
  because we require one minute of heartbeat activity to rescue orphaned jobs.

- [Oban.Queue.Producer] Introduce "dispatch cooldown" as a way to debounce
  repeatedly fetching new jobs. Repeated fetching floods the producer's message
  queue and forces the producer to repeatedly fetch one job at a time, which is
  not especially efficient. Debounced fetching is much more efficient for the
  producer and the database, increasing maximum jobs/sec throughput so that it
  scales linearly with a queue's concurrency settings (up to what the database
  can handle).

- [Oban.Query] Discard jobs that have exhausted the maximum attempts rather than
  rescuing them. This prevents repeatedly attempting a job that has consistently
  crashed the BEAM.

- [Oban.Query] Use transactional locks to prevent duplicate inserts without
  relying on unique constraints in the database. This provides strong unique
  guarantees without requiring migrations.

### Removed

- [Oban.Notifications] An overhauled and simplified insert trigger no longer
  emits `update` notifications. This was largely an internal implementation
  detail and wasn't publicly documented, but it does effect the UI.

## [0.12.1] — 2019-12-13

### Fixed

- [Oban.Worker] Deep merge `unique` options between the worker and custom
  params. Previously the `unique` options passed to `Worker.new/2` would
  completely override the options stored by `use Oban.Worker`. This was
  primarily an issue for crontab jobs, where the period is always passed by the
  scheduler.

### Changed

- [Oban] Allow setting `crontab: false` or `crontab: nil` to disable scheduling.
  This matches the `queues` behavior and makes it possible to override the
  default configuration within each environment, i.e. when testing.

- [Oban.Testing] Better error message for `Oban.Testing.assert_enqueued/2`

## [0.12.0] – 2019-11-26

**Migration Optional (V7)**

The queries used to prune by limit and age are written to utilize a single
partial index for a huge performance boost on large tables. The new V7 migration
will create the index for you—but that may not be ideal for tables with millions
of completed or discarded jobs because it can't be done concurrently.

If you have an extremely large jobs table you can add the index concurrently in
a dedicated migration:

```elixir
create index(
         :oban_jobs,
         ["attempted_at desc", :id],
         where: "state in ('completed', 'discarded')",
         name: :oban_jobs_attempted_at_id_index,
         concurrently: true
       )
```

### Added

- [Oban] Add `start_queue/3` and `stop_queue/2` for dynamically starting and
  stopping supervised queues across nodes.

- [Oban] Add `drain_queue/3` to accept drain options. `with_scheduled: true`
  allows draining scheduled jobs.

- [Oban] Expose `circuit_backoff` as a "twiddly" option that controls how long
  tripped circuit breakers wait until re-opening.

- [Oban.Testing] Accept a value/delta tuple for testing timestamp fields. This
  allows more robust testing of timestamps such as `scheduled_at`.

- [Oban.Telemetry] Emit `[:oban, :trip_circuit]` and `[:oban, :open_circuit]`
  events for circuit breaker activity. Previously an error was logged when the
  circuit was tripped, but there wasn't any way to monitor circuit breakers.

  Circuit breaker activity is logged by the default telemetry logger (both
  `:trip_circuit` and `:open_circuit` events).

### Fixed

- [Oban.Query] Avoid using prepared statements for all unique queries. This
  forces Postgres to use a custom plan (which utilizes the compound index)
  rather than falling back to a generic plan.

- [Oban.Job] Include all permitted fields when converting a Job to a map,
  preserving any optional values that were either specified by the user or came
  via Worker defaults.

- [Oban.Migrations] Guard against missing migration modules in federated
  environments.

### Changed

- [Oban] Allow the multi `name` provided to `Oban.insert/3,4` to be any term,
  not just an atom.

- [Oban.Query] Use a consistent and more performant set of queries for pruning.
  Both pruning methods are optimized to utilize a single partial index.

## [0.11.1] — 2019-11-13

### Fixed

- [Oban.Pruner] Apply `prune_limit` when pruning beats. A _lot_ of beats can
  accumulate when pruning has been disabled. Later, when pruning is enabled,
  the pruner would try to delete too many beats and would time out.

- [Oban.Crontab.Scheduler] Use a zero arity function for the transaction
  callback. The one arity version is only available in Ecto >= 3.2.

## [0.11.0] — 2019-11-06

**Migration Optional (V6)**

Job id's greater than 2,147,483,647 (PG `int` limit) can't be inserted into the
running array on `oban_beats`. The array that Ecto defines uses `int` instead of
`bigint`, which can't store the larger integers. This migration changes the
column type to `bigint[]`, a locking operation that may take a few seconds.

### Added

- [Oban] Added `crontab` support for automatically enqueuing jobs on a fixed
  schedule. A combination of transactional locks and unique jobs prevents
  scheduling duplicate jobs.

### Fixed

- [Oban.Migrations] Add a comment when migrating `oban_jobs` to V5 and when
  rolling back down to V4.

- [Oban.Query] Apply the configured log level to unique queries.

- [Oban.Notifier] Prevent open connections from accumulating when the circuit is
  tripped during the connection phase. This change may leave notifications in a
  state where they aren't listening to all channels.

### Changed

- [Oban.Notifier] Replay `oban_update` notifications to subscribed processes.

## [0.10.1] — 2019-10-08

### Changed

- [Oban.Notifier] Replay `oban_gossip` notifications to subscribed processes.

## [0.10.0] — 2019-10-03

**Migration Optional (V5)**

Tables with a _lot_ of available jobs (hundreds of thousands to several million)
are prone to time outs when fetching new jobs. The planner fails to optimize
using the index available on `queue`, `state` and `scheduled_at`, forcing both a
slow sort pass and an expensive bitmap heap scan.

This migration drops the separate indexes in favor of a a single composite
index. The resulting query is up to **258,757x faster** on large tables while
still usable for all of the other maintenance queries.

History of the `EXPLAIN ANALYZE` output as the query was optimized is available
here: https://explain.depesz.com/s/9Vh7

### Changed

- [Oban.Config] Change the default for `verbose` from `true` to `false`. Also,
  `:verbose` now accepts _only_ `false` and standard logger levels.  This change
  aims to prevent crashes due to conflicting levels when the repo's log level is
  set to `false`.

### Fixed

- [Oban.Notifier] Restructure the notifier in order to to isolate producers from
  connection failures. Errors or loss of connectivity in the notification
  connection no longer kills the notifier and has no effect on the producers.

## [0.9.0] — 2019-09-20

### Added

- [Oban] Add `insert_all/2` and `insert_all/4`, corresponding to
  `c:Ecto.Repo.insert_all/3` and `Ecto.Multi.insert_all/5`, respectively.

- [Oban.Job] Add `to_map/1` for converting a changeset into a map suitable for
  database insertion. This is used by `Oban.insert_all/2,4` internally and is
  exposed for convenience.

### Changed

- [Oban.Config] Remove the default queue value of `[default: 10]`, which was
  overriden by `Oban.start_link/1` anyhow.

- [Oban.Telemetry] Allow the log level to be customized when attaching the
  default logger. The default level is `:info`, the same as it was before.

### Fixed

- [Oban.Migrations] Prevent invalid `up` and `down` _targets_ when attempting to
  run migrations that have already been ran. This was primarily an issue in CI,
  where the initial migration was unscoped and would migrate to the current
  version while a subsequent migration would attempt to migrate to a lower
  version.

- [Oban.Job] Prevent a queue comparison with `nil` by retaining the default
  queue (`default`) when building uniqueness checks.

- [Oban.Job] Set state to `scheduled` for jobs created with a `scheduled_at`
  timestamp. Previously the state was only set when `schedule_in` was used.

## [0.8.1] — 2019-09-11

### Changed

- [Oban.Notifier] Restore the `gossip` macro and allow `oban_gossip` channel for
  notifications.

### Fixed

- [Oban.Migrations] Prevent invalid `up` and `down` ranges when repeatedly
  migrating without specifying a version. This issue was seen when running all
  of the `up` migrations on a database from scratch, as there would be multiple
  oban migrations that simply delegated to `up` and `down`.

## [0.8.0] — 2019-09-06

**Migration Required (V4)**

This release **requires** a migration to V3, with an optional migration to V4.
V3 adds a new column to jobs and creates the `oban_beats` table, while V4 drops
a function used by the old advisory locking system.

For a smooth zero-downtime upgrade, migrate to V3 first and then V4 in a separate
release. The following sample migration will only upgrade to V3:

```elixir
defmodule MyApp.Repo.Migrations.AddObanBeatsTable do
  use Ecto.Migration

  def up do
    Oban.Migrations.up(version: 3)
  end

  def down do
    Oban.Migrations.down(version: 2)
  end
end
```

### Added

- [Oban.Job] Add an `attempted_by` column used to track the node, queue and
  producer nonce that attempted to execute a job.

- [Oban.Beat] Add a new `oban_beats` table, used by producers to publish "pulse"
  information including the node, queue, running jobs and other information
  previously published by gossip notifications.

  Beat records older than one hour are pruned automatically. Beat pruning
  respects the `:disabled` setting, but it ignores length and age configuration.
  The goal is to prevent bloating the table with useless historic
  information—each queue generates one beat a second, 3,600 beat records per
  hour even when the queue is idle.

### Changed

- [Oban.Executor] Don't swallow an `ArgumentError` when raised by a worker's
  `backoff` function.

- [Oban.Notifier] Remove `gossip` notifications entirely, superseded by pulse
  activity written to `oban_beats`.

- [Oban.Query] Remove all use of advisory locks!

- [Oban.Producer] Periodically attempt to rescue orphans, not just at startup.
  By default a rescue is attempted once a minute and it checks for any executing
  jobs belonging to a producer that hasn't had a pulse for more than a minute.

### Fixed

- [Oban.Worker] Validate worker options after the module is compiled. This
  allows dynamic configuration of compile time settings via module attributes,
  functions, `Application.get_env/3`, etc.

- [Oban.Query] Remove `scheduled_at` check from job fetching query. This could
  prevent available jobs from dispatching when the database's time differed from
  the system time.

- [Oban.Migrations] Fix off-by-one error when detecting the version to migrate
  up from.

## [0.7.1] — 2019-08-15

### Fixed

- [Oban.Query] Release advisory locks in batches rather than individually after
  a job finishes execution. By tracking unlockable jobs and repeatedly
  attempting to unlock them for each connection we ensure that eventually all
  advisory locks are released.

  The previous unlocking system leaked advisory locks at a rate proportional to
  the number of connections in the db pool. The more connections, the more locks
  that wouldn't release. With a default value of 64 for `max_locks_per_transaction`
  the database would raise "ERROR:  53200: out of shared memory" after it hit a
  threshold (11,937 exactly, in my testing).

- [Oban.Worker] Allow `max_attempts` to be 1 or more. This used to be possible
  and was broken unintentionally by compile time validations.

## [0.7.0] — 2019-08-08

### Added

- [Oban] Added `insert/2`, `insert!/2` and `insert/4` as a convenient and more
  powerful way to insert jobs. Features such as unique jobs and the upcoming
  prefix support only work with `insert`.

- [Oban] Add `prefix` support. This allows entirely isolated job queues within
  the same database.

- [Oban.Worker] Compile time validation of all passed options. Catch typos and
  other invalid options when a worker is compiled rather than when a job is
  inserted for the first time.

- [Oban.Worker] Unique job support through the `unique` option. Set a unique
  period, and optionally `fields` and `states`, to enforce uniqueness within a
  window of time. For example, to make a job unique by args, queue and worker
  for 2 minutes:

  `use Oban.Worker, unique: [period: 120, fields: [:args, :queue, :worker]]`

  Note, unique support relies on the use of `Oban.insert/2,4`.

### Changed

- [Oban.Worker] Remove the `perform/1` callback in favor of `perform/2`. The new
  `perform/2` function receives the job's args, followed by the complete job
  struct. This new function signature makes it clear that the args are always
  available, and the job struct is also there when it is needed. A default
  `perform/2` function _is not_ generated automatically by the `use` macro and
  _must_ be defined manually.

  This is a breaking change and all worker modules will need to be updated.
  Thankfully, due to the behaviour change, warnings will be emitted when you
  compile after the upgrade.

  If your perform functions weren't matching on the `Oban.Job` struct then
  you can migrate your workers by adding a second `_job` argument:

  `def perform(%{"some" => args}, _job)`

  If you were making use of `Oban.Job` metadata in `perform/1` then you can move
  the job matching to the second argument:

  `def perform(_args, %{attempt: attempt})`

  See [the issue that suggested this change][i45] for more details and
  discussion.

- [Oban.Producer] Use `send_after/3` instead of `:timer.send_interval/2` to
  maintain scheduled dispatch. This mechanism is more accurate under system
  load and it prevents `:poll` messages from backing up for each producer.

- [Oban.Migration] Accept a keyword list with `:prefix` and `:version` as
  options rather than a single version string. When a prefix is supplied the
  migration will create all tables, indexes, functions and triggers within that
  namespace. For example, to create the jobs table within a "private" prefix:

  `Oban.Migrate.up(prefix: "private")`

[i45]: https://github.com/sorentwo/oban/issues/45

## [0.6.0] — 2019-07-26

### Added

- [Oban.Query] Added `:verbose` option to control general query logging. This
  allows `debug` query activity within Oban to be silenced during testing and
  development.

- [Oban.Testing] Added `all_enqueued/1` helper for testing. The helper returns
  a list of jobs matching the provided criteria. This makes it possible to test
  using pattern matching, which is more flexible than a literal match within the
  database.

### Changed

- [Oban.Config] All passed options are validated. Any unknown options will raise
  an `ArgumentError` and halt startup. This prevents misconfiguration through
  typos and passing unsupported options.

- [Oban.Worker] The `perform/1` function now receives an `Oban.Job` struct as
  the sole argument, calling `perform/1` again with only the `args` map if no
  clause catches the struct. This allows workers to use any attribute of the job
  to customize behaviour, e.g. the number of attempts or when a job was inserted
  into the database.

  The implementation is entirely backward compatible, provided workers are
  defined with the `use` macro. Workers that implement the `Oban.Worker`
  behaviour manually will need to change the signature of `perform/1` to accept
  a job struct.

- [Oban] Child process names are generated from the top level supervisor's name,
  i.e. setting the name to "MyOban" on `start_link/1` will set the notifier's
  name to `MyOban.Notifier`. This improves isolation and allows multiple
  supervisors to be ran on the same node.

### Fixed

- [Oban.Producer] Remove duplicate polling timers. As part of a botched merge
  conflict resolution two timers were started for each producer.

## [0.5.0] — 2019-06-27

### Added

- [Oban.Pruner] Added `:prune_limit` option to constrain the number of rows
  deleted on each prune iteration. This prevents locking the database when there
  are a large number of jobs to delete.

### Changed

- [Oban.Worker] Treat `{:error, reason}` tuples returned from `perform/1` as a
  failure. The `:kind` value reported in telemetry events is now differentiated,
  where a rescued exception has the kind `:exception`, and an error tuple has
  the kind `:error`.

### Fixed

- [Oban.Testing] Only check `available` and `scheduled` jobs with the
  `assert|refute_enqueued` testing helpers.

- [Oban.Queue.Watchman] Catch process exits when attempting graceful shutdown.
  Any exits triggered within `terminate/2` are caught and ignored. This safely
  handles situations where the producer exits before the watchman does.

- [Oban.Queue.Producer] Use circuit breaker protection for gossip events and
  call queries directly from the producer process. This prevents pushing all
  queries through the `Notifier`, and ensures more granular control over gossip
  errors.

## [0.4.0] — 2019-06-10

### Added

- [Oban] Add `Oban.drain_queue/1` to help with integration testing. Draining a
  queue synchronously executes all available jobs in the queue from within the
  calling process. This avoids any sandbox based database connection issues and
  prevents race conditions from asynchronous processing.

- [Oban.Worker] Add `backoff/1` callback and switch to exponential backoff with
  a base value as the default. This allows custom backoff timing for individual
  workers.

- [Oban.Telemetry] Added a new module to wrap a default handler for structured
  JSON logging. The log handler is attached by calling
  `Oban.Telemetry.attach_default_logger/0` somewhere in your application code.

- [Oban.Queue.Producer] Guard against Postgrex errors in all producer queries
  using a circuit breaker. Failing queries will no longer crash the producer.
  Instead, the failure will be logged as an error and it will trip the
  producer's circuit breaker. All subsequent queries will be skipped until the
  breaker is enabled again approximately a minute later.

  This feature simplifies the deployment process by allowing the application to
  boot and stay up while Oban migrations are made. After migrations have
  finished each queue producer will resume making queries.

### Changed

- [Oban] Telemetry events now report timing as `%{duration: duration}` instead
  of `%{timing: timing}`. This aligns with the `telemetry` standard of using
  `duration` for the time to execute something.

- [Oban] Telemetry events are now broken into `success` and `failure` at the
  event level, rather than being labeled in the metadata. The full event names
  are now `[:oban, :success]` and `[:oban, :failure]`.

- [Oban.Job] Rename `scheduled_in` to `schedule_in` for readability and
  consistency. Both the `Oban` docs and README showed `schedule_in`, which reads
  more clearly than `scheduled_in`.

- [Oban.Pruner] Pruning no longer happens immediately on startup and may be
  configured through the `:prune_interval` option. The default prune interval is
  still one minute.

### Fixed

- [Oban.Migrations] Make partial migrations more resilient by guarding against
  missing versions and using idempotent statements.

## [0.3.0] - 2019-05-29

**Migration Required (V2)**

### Added

- [Oban] Allow setting `queues: false` or `queues: nil` to disable queue
  dispatching altogether. This makes it possible to override the default
  configuration within each environment, i.e. when testing.

  The docs have been updated to promote this mechanism, as well as noting that
  pruning must be disabled for testing.

- [Oban.Testing] The new testing module provides a set of helpers to make
  asserting and refuting enqueued jobs within tests much easier.

### Changed

- [Oban.Migrations] Explicitly set `id` as a `bigserial` to avoid mistakenly
  generating a `uuid` primary key.

- [Oban.Migrations] Use versioned migrations that are immutable. As database
  changes are required a new migration module is defined, but the interface of
  `Oban.Migrations.up/0` and `Oban.Migrations.down/0` will be maintained.

  From here on all releases _with_ database changes will indicate that a new
  migration is necessary in this CHANGELOG.

- [Oban.Query] Replace use of `(bigint)` with `(int, int)` for advisory locks.
  The first `int` acts as a namespace and is derived from the unique `oid` value
  for the `oban_jobs` table. The `oid` is unique within a database and even
  changes on repeat table definitions.

  This change aims to prevent lock collision with application level advisory
  lock usage and other libraries. Now there is a 1 in 2,147,483,647 chance of
  colliding with other locks.

- [Oban.Job] Automatically remove leading "Elixir." namespace from stringified
  worker name. The prefix complicates full text searching and reduces the score
  for trigram matches.

## [0.2.0] - 2019-05-15

### Added

- [Oban] Add `pause_queue/2`, `resume_queue/2` and `scale_queue/3` for
  dynamically controlling queues.
- [Oban] Add `kill_job/2` for terminating running jobs and marking them as
  discarded.
- [Oban] Add `config/0` for retreiving the supervisors config. This is primarily
  useful for integrating oban into external applications.
- [Oban.Queue.Producer] Use database triggers to immediately dispatch when a job
  is inserted into the `oban_jobs` table.
- [Oban.Job] Execution errors are stored as a jsonb array for each job. Each
  error is stored, not just the most recent one. Error entries contains these
  keys:
  - `at` The utc timestamp when the error occurred at
  - `attempt` The attempt number when the error ocurred
  - `error` A formatted error message and stacktrace, passed through
    `Exception.blame/3`
- [Oban.Config] Validate all options based on type and allowed values. Any
  invalid option will raise, preventing supervisor boot.
- [Oban.Notifier] Broadcast runtime gossip through pubsub, allowing any
  external system to get stats at the node and queue level.

### Changed

- [Oban.Queue.Supervisor] Set the `min_demand` to 1 for all consumers. This
  ensures that each queue will run the configured number of concurrent jobs. By
  default the `min_demand` is half of `max_demand`, which means a few slow jobs
  can prevent the queue from running the expected number of concurrent jobs.
- [Oban.Job] Change psuedo-states based on job properties into fixed states,
  this applies to `scheduled` and `retryable`.
- [Oban.Job] The "Elixir" prefix is stripped from worker names before storing
  jobs in the database. Module lookup performs the same way, but it cleans up
  displaying the worker name as a string.
- [Oban.Job] Accept all job fields as changeset parameters. While not
  encouraged for regular use, this is essential for testing various states.

## [0.1.0] - 2019-03-10

- [Oban] Initial release with base functionality.

[Unreleased]: https://github.com/sorentwo/oban/compare/v2.3.3...HEAD
[2.3.3]: https://github.com/sorentwo/oban/compare/v2.3.2...v2.3.3
[2.3.2]: https://github.com/sorentwo/oban/compare/v2.3.1...v2.3.2
[2.3.1]: https://github.com/sorentwo/oban/compare/v2.3.0...v2.3.1
[2.3.0]: https://github.com/sorentwo/oban/compare/v2.2.0...v2.3.0
[2.2.0]: https://github.com/sorentwo/oban/compare/v2.1.0...v2.2.0
[2.1.0]: https://github.com/sorentwo/oban/compare/v2.0.0...v2.1.0
[2.0.0]: https://github.com/sorentwo/oban/compare/v2.0.0-rc.3...v2.0.0
[2.0.0-rc.3]: https://github.com/sorentwo/oban/compare/v2.0.0-rc.2...v2.0.0-rc.3
[2.0.0-rc.2]: https://github.com/sorentwo/oban/compare/v2.0.0-rc.1...v2.0.0-rc.2
[2.0.0-rc.1]: https://github.com/sorentwo/oban/compare/v2.0.0-rc.0...v2.0.0-rc.1
[2.0.0-rc.0]: https://github.com/sorentwo/oban/compare/v1.2.0...v2.0.0-rc.0
[1.2.0]: https://github.com/sorentwo/oban/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/sorentwo/oban/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/sorentwo/oban/compare/v1.0.0-rc.1...v1.0.0
[1.0.0-rc.2]: https://github.com/sorentwo/oban/compare/v1.0.0-rc.1...v1.0.0-rc.2
[1.0.0-rc.1]: https://github.com/sorentwo/oban/compare/v0.12.1...v1.0.0-rc.1
[0.12.1]: https://github.com/sorentwo/oban/compare/v0.12.0...v0.12.1
[0.12.0]: https://github.com/sorentwo/oban/compare/v0.11.1...v0.12.0
[0.11.1]: https://github.com/sorentwo/oban/compare/v0.11.0...v0.11.1
[0.11.0]: https://github.com/sorentwo/oban/compare/v0.10.1...v0.11.0
[0.10.1]: https://github.com/sorentwo/oban/compare/v0.10.0...v0.10.1
[0.10.0]: https://github.com/sorentwo/oban/compare/v0.9.0...v0.10.0
[0.9.0]: https://github.com/sorentwo/oban/compare/v0.8.1...v0.9.0
[0.8.1]: https://github.com/sorentwo/oban/compare/v0.8.0...v0.8.1
[0.8.0]: https://github.com/sorentwo/oban/compare/v0.7.1...v0.8.0
[0.7.1]: https://github.com/sorentwo/oban/compare/v0.7.0...v0.7.1
[0.7.0]: https://github.com/sorentwo/oban/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/sorentwo/oban/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/sorentwo/oban/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/sorentwo/oban/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/sorentwo/oban/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/sorentwo/oban/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/sorentwo/oban/compare/0ac3cc8...v0.1.0
