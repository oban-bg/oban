# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](http://semver.org/spec/v2.0.0.html).

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
[0.2.0]: https://github.com/sorentwo/oban/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/sorentwo/oban/compare/0ac3cc8...v0.1.0
