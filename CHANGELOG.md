# Changelog

All notable changes to `Oban` are documented in this file.

## [2.5.0] — 2021-02-26

### Top of the Minute Cron

Rather than scheduling cron evaluation 60 seconds after the server starts,
evaluation is now scheduled at the top of the next minute. This yields several
improvements:

- More predictable timing for cron jobs now that they are inserted at the top of
  the minute. Note that jobs may execute later depending on how busy queues are.
- Minimize contention between servers inserting jobs, thanks to the transaction
  lock acquired by each plugin.
- Prevent duplicate inserts for jobs that omit the `completed` state (when
  server start time is staggered the transaction lock has no effect)

### Repeater Plugin for Transaction Pooled Databases

Environments that can't make use of PG notifications, i.e. because they use
PgBouncer with transaction pooling, won't process available jobs reliably. The
new `Repeater` plugin provides a workaround that simulates polling functionality
for producers.

Simply include the `Repeater` in your plugin list:

```elixir
config :my_app, Oban,
  plugins: [
    Oban.Plugins.Pruner,
    Oban.Plugins.Stager,
    Oban.Plugins.Repeater
  ],
  ...
```

### Include Perform Result in Job Telemetry Metadata

The metadata for `[:oban, :job, :stop]` telemetry events now include the job's
`perform/1` return value. That makes it possible to extract job output from
other processes:

```elixir
def handle_event([:oban, :job, :stop], _timing, meta, _opts) do
  IO.inspect(meta.result, label: "return from #{meta.job.worker}")

  :ok
end
```

### Added

- [Oban] Support a changeset function in addition to a changeset in
  `insert_all/4`. Inserting jobs within a multi is even more powerful.

- [Oban.Queue.Executor] Stash a timed job's pid to enable inner process
  messaging, notably via telemetry events.

### Changed

- [Oban] Upgrade minimum Elixir version from 1.8 to 1.9.

- [Oban.Plugins.Cron] Individually validate crontab workers and options,
  providing more descriptive errors at the collection and entry level.

- [Oban] Simplify the job cancelling flow for consistency. Due to race
  conditions it was always possible for a job to complete before it was
  cancelled, now that flow is much simpler.

- [Oban.Queue.Producer] Replace dispatch cooldown with a simpler debounce
  mechanism.

- [Oban.Plugins.Stager] Limit the number of notify events to one per queue,
  rather than one per available job.

### Fixed

- [Oban.Queue.Producer] Handle unclean exits without an error and stack, which
  prevents "zombie" jobs. This would occur after multiple hot upgrades when the
  worker module changed, as the VM would forcibly terminate any processes
  running the old modules.

- [Oban] Specify that the `changeset_wrapper` type allows keys other than
  `:changesets`, fixing a dialyzer type mismatch.

### Removed

- [Oban] Remove the undocumented `version/0` function in favor of using the
  standard `Application.spec/2`

## [2.4.3] — 2021-02-07

### Fixed

- [Oban.Telemetry] Use `conf` rather than `config` in meta for `:job` and
  `:circuit` telemtry events.

## [2.4.2] — 2021-01-28

### Fixed

- [Oban.Plugins.Stager] Notify queues of all available jobs, not only jobs that
  were most recently staged. In some circumstances, such as reboot or retries,
  jobs are available without previously being scheduled.

## [2.4.1] — 2021-01-27

### Fixed

- [Oban.Migrations] Correctly migrate up between sequential versions. The V10
  migration adds check constraints, which can't be re-run safely. An attempted
  work-around prevented re-runs, but broke sequential upgrades like 9->10.

- [Oban.Queue.Producer] Kick off an initial dispatch to start processing
  available jobs on startup, to compensate for a lack of incoming jobs or
  scheduling.

- [Oban.Plugins.Stager] Keep rescheduling staging messages after the initial
  run.

## [2.4.0] — 2021-01-26

### Centralized Stager Plugin

Queue producers no longer poll every second to stage scheduled jobs. Instead,
the new `Oban.Plugins.Stager` plugin efficiently handles staging from a single
location. This reduces overall load on the BEAM and PostgreSQL, allowing apps to
easily run hundreds of queues simultaneously with little additional overhead.

In a test with a single Ecto connection and **512 queues** the CPU load went
from 60.0% BEAM / 21.5% PostgreSQL in v2.3.4 to 0.5% BEAM / 0.0% PostgreSQL.

The stager plugin is automatically injected into Oban instances and there isn't
any additional configuration necessary. However, if you've set a `poll_interval`
for Oban or an individual queue you can safely remove it.

### Overhauled Cron

The CRON parser is entirely rewritten to be simpler and _dramatically_ smaller.
The previous parser was built on `nimble_parsec` and while it was fast, the
compiled parser added ~5,500LOC to the code base. Thanks to a suite of property
tests we can be confident that the new parser behaves identically to the
previous one, and has much clearer error messages when parsing fails.

Along with a new parser the `crontab` functionality is extracted into the
`Oban.Plugins.Cron` plugin. For backward compatibility, top-level `crontab` and
`timezone` options are transformed into a plugin declaration. If you'd like to
start configuring the plugin directly change your config from:

    config :my_app, Oban,
      crontab: [{"* * * * *", MyApp.Worker}],
      timezone: "America/Chicago"
      ...

To this:

    config :my_app, Oban,
      plugins: [
        {Oban.Plugins.Cron,
         crontab: [{"* * * * *", MyApp.Worker}],
         timezone: "America/Chicago"}
      ]

The plugin brings a cleaner implementation, simplified supervision tree, and
eliminates the need to set `crontab: false` in test configuration.

### Improved Indexes for Unique Jobs

Applications may have thousands to millions of completed jobs in storage. As the
table grows the performance of inserting unique jobs can slow drastically. A new
V10 migration adds necessary indexes, and paired with improved query logic it
alleviates insert slowdown entirely.

For comparison, a local benchmark showed that in v2.3.4 inserting a unique job
into a table of 1 million jobs runs around 4.81 IPS. In v2.4.0 it runs at 925.34
IPS, nearly **200x faster**.

The V10 migration is optional. If you decide to migrate, first create a new
migration:

```bash
mix ecto.gen.migration upgrade_oban_jobs_to_v10
```

Next, call `Oban.Migrations` in the generated migration:

```elixir
defmodule MyApp.Repo.Migrations.UpdateObanJobsToV10 do
  use Ecto.Migration

  def up do
    Oban.Migrations.up(version: 10)
  end

  def down do
    Oban.Migrations.down(version: 10)
  end
end
```

### Added

- [Oban] Add `[:oban, :supervisor, :init]` event emitted when an Oban supervisor
  starts.

- [Oban.Telemetry] Wrap built-in plugins with telemetry spans and consistently
  include `conf` in all telemetry events.

- [Oban.Config] Improve the error messages raised during initial validation.
  Also, the `Config` module is now public with light documentation.

- [Oban.Testing] Support specifying a default prefix for all test assertions.
  This comes with improved assertion messages that now include the prefix.

- [Oban.Repo] Add `delete/3` as a convenient wrapper around
  `c:Ecto.Repo.delete/2`.

- [Oban.Job] New check constraints prevent inserting jobs with an invalid
  `priority`, negative `max_attempts` or an `attempt` number beyond the maximum.

### Changed

- [Oban.Telemetry] Deprecate and replace `span/3` usage in favor of the official
  `:telemetry.span/3`, which wasn't available when `span/3` was implemented.

### Fixed

- [Oban] Inspect the error reason for a failed `insert!/2` call before it is
  raised as an error. When `insert!/2` was called in a transaction the error
  could be `:rollback`, which wasn't a valid error.

## [2.3.4] — 2020-12-02

### Fixed

- [Oban.Worker] Update `from_string/1` to correctly work with modules that
  weren't loaded.

## [2.3.3] — 2020-11-10

### Changed

- [Oban.Migration] Conditionally skip altering `oban_job_state` if the
  `cancelled` state is already present. This allows for a smoother upgrade path
  for users running PG < 12. See the notes for v2.3.0 for more details.

## [2.3.2] — 2020-11-06

### Fixed

- [Oban.Migration] Restore indexes possibly removed by changing
  `oban_job_state`. This only applies to PG older than version 12.

- [Oban.Plugins.Pruner] Prune `cancelled` jobs along with `completed` or
  `discarded`.

## [2.3.1] — 2020-11-06

### Changed

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

  def up do
    Oban.Migrations.up(version: 9)
  end

  def down do
    Oban.Migrations.down(version: 9)
  end
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

- [Oban] Removed `kill_job/2`, which wasn't as flexible as `Oban.cancel_job/2`.

  Use `Oban.cancel_job/2` instead to safely discard scheduled jobs or killing
  executing jobs.

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
  `with_safety: false` as an option to `Oban.drain_queue/2`.

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

For changes prior to 2.0 see the [1.2 branch][1.2]

[Unreleased]: https://github.com/sorentwo/oban/compare/v2.5.0...HEAD
[2.5.0]: https://github.com/sorentwo/oban/compare/v2.4.3...v2.5.0
[2.4.3]: https://github.com/sorentwo/oban/compare/v2.4.2...v2.4.3
[2.4.2]: https://github.com/sorentwo/oban/compare/v2.4.1...v2.4.2
[2.4.1]: https://github.com/sorentwo/oban/compare/v2.4.0...v2.4.1
[2.4.0]: https://github.com/sorentwo/oban/compare/v2.3.4...v2.4.0
[2.3.4]: https://github.com/sorentwo/oban/compare/v2.3.3...v2.3.4
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
[1.2]: https://github.com/sorentwo/oban/tree/1.2
