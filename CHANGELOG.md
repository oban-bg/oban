# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](http://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- [Oban.Pruner] Added `prune_limit` option to constrain the number of rows 
  deleted on each prune iteration. This prevents locking the database when
  there are a large number of jobs to delete.

### Fixed

- [Oban.Testing] Only check `available` and `scheduled` jobs with the
  `assert|refute_enqueued` testing helpers.

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

[Unreleased]: https://github.com/sorentwo/oban/compare/v0.2.0...HEAD
[0.4.0]: https://github.com/sorentwo/oban/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/sorentwo/oban/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/sorentwo/oban/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/sorentwo/oban/compare/0ac3cc8...v0.1.0
