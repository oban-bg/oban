# Changelog for Oban v2.15

_🌟 Looking for changes to Web or Pro? Check the [Oban.Pro Changelog][opc] or
the [Oban.Web Changelog][owc]. 🌟_

## 🗜️ Notification Compression

Oban uses notifications across most core functionality, from job staging to cancellation. Some
notifications, such as gossip, contain massive redundancy that compresses nicely. For example,
this table breaks down the compression ratios for a fairly standard gossip payload
containing data from ten queues:

| Mode      | Bytes | % of Original |
| --------- | ----- | ------------- |
| Original  | 4720  | 100%          |
| Gzip      | 307   |   7%          |
| Encode 64 | 412   |   9%          |

Minimizing notification payloads is especially important for Postgres because it applies an 8kb
limit to all messages. Now all pub/sub notifications are compressed automatically, with a safety
mechanism for compatibility with external notifiers, namely Postgres triggers.

## 🗃️ Query Improvements

There has been an ongoing issue with systems recording a job attempt twice, when it only executed
once. While that sounds minor, it could break an entire queue when the attempt exceeded max
attempts because it would violate a database constraint.

Apparently, the Postgres planner may choose to generate a plan that executes a nested loop over
the LIMITing subquery, causing more UPDATEs than LIMIT. That could cause unexpected updates,
including attempts > max_attempts in some cases. The solution is to use a CTE as an "optimization
fence" that forces Postgres _not_ to optimize the query.

We also worked in a few additional query improvements:

* Use an index only scan for job staging to safely handle tables with millions of scheduled jobs.
* Remove unnecessary row locking from staging and pruning queries.

## 🪶 New Engine Callbacks for SQL Compatibility

We're pleased to share improvements in Oban's SQLite integration. A few SQLite pioneers identified
pruning and staging compatibility bugs, and instead of simply patching around the issues with
conditional logic, we tackled them with new engine callbacks: `stage_jobs/3` and `prune_jobs/3`.
The result is safer, optimized queries for each specific database.

Introducing new engine callbacks with database-specific queries paves the way for working with
other databases. There's even an [open issue for MySQL support][mysql]...

[mysql]: https://github.com/sorentwo/oban/issues/836

## v2.15.4 — 2023-08-07

### Enhancements

- [Testing] Accept all config options in perform_job/3

  Testing with `perform_job/3` requires building a viable config object. Previously, only a few
  select options like `repo` were forwarded, which hampered the ability to tweak config for
  testing.

### Bug Fixes

- [PG] Remove monitored processes from listeners list

  The PG notifier monitored listener processes but didn't remove them from the set when a listener
  exited. Busy systems would gradually accumulate dead pids and kept dispatching to them,
  bottlnecking the PG process and eventually calling timeouts for new listeners.

## v2.15.3 — 2023-08-04

### Enhancements

- [Pruner] Prune jobs using the `scheduled_at` timestamp regardless of state.

  The previous pruning query checked a different timestamp field for each prunable state, e.g.
  `cancelled` used `cancelled_at`. There aren't any indexes for those timestamps, let alone the
  combination of each state and timestamp, which led to slow pruning queries in larger databases.

  In a database with a mixture of ~1.2m prunable jobs the updated query is 130x faster, reducing
  the query time from 177ms down to 1.3ms.

- [Lite] Avoid unnecessary transactions during staging and pruning operations

  Contention between SQLite3 transactions causes deadlocks that lead to period errors. Avoiding
  transactions when there isn't anything to write minimizes contention.

### Bug Fixes

- [Foreman] Explicitly pause queues when shutdown begins.

  A call to `Producer.shutdown/1` was erroneously removed during the `DynamicSupervisor` queue
  refactor.

- [Job] Preserve explicit state set along with `scheduled_in` time.

  The presence of a `scheduled_in` timestamp would always set the state to `scheduled`, even when
  an explicit state was passed.

## v2.15.2 — 2023-06-22

### Enhancements

- [Repo] Pass `oban: true` option to all queries.

  Telemetry options are exposed in Ecto instrumentation, but they aren't obviously available in the
  opts passed to `prepare_query`. Now all queries have an `oban: true` option so users can ignore
  them in multi-tenancy setups.

- [Engine] Generate a UUID for all `Basic` and `Lite` queue instances to aid in identifying
  orphaned jobs or churning queue producers.

- [Oban] Use `Logger.warning/2` and replace deprecated use of `:warn` level with `:warning`
  across all modules.

### Bug Fixes

- [Job] Validate changesets during `Job.to_map/1` conversion

  The `Job.to_map/1` function converts jobs to a map "entry" suitable for use in `insert_all`.
  Previously, that function didn't perform any validation and would allow inserting (or attempting
  to insert) invalid jobs during `insert_all`. Aside from inconsistency with `insert` and
  `insert!`, `insert_all` could insert invalid jobs that would never run successfully.
  
  Now `to_map/1` uses `apply_action!/2` to apply the changeset with validation and raises an
  exception identical to `insert!`, but before calling the database.

- [Notifier] Store PG notifier state in the registry for non-blocking lookup

  To avoid `GenServer.call` timeouts when the system is under high load we pull the state from the
  notifier's registry metadata.

- [Migration] Add `primary_key` explicitly during SQLite3 migrations

  If a user has configured Ecto's `:migration_primary_key` to something other than `bigserial` the
  schema is incompatible with Oban's job schema.

## v2.15.1 — 2023-05-11

### Enhancements

- [Telemetry] Add `[:oban, :stager, :switch]` telemetry event and use it for logging changes.

  Aside from an instrumentable event, the new logs are structured for consistent parsing on
  external aggregators.

- [Job] Remove default priority from job schema to allow changing defaults through the database
    
### Bug Fixes

- [Basic] Restore `attempt < max_attempts` condition when fetching jobs

  In some situations, a condition to ensure the attempts don't exceed max attempts is still
  necessary. By checking the attempts _outside_ the CTE we maintain optimal query performance for
  the large scan that finds jobs, and only apply the check in the small outer query.

- [Pruner] Add missing `:interval` to `t:Oban.Plugins.Pruner.option/0`

## v2.15.0 — 2023-04-13

### Enhancements

- [Oban] Use DynamicSupervisor to supervise queues for optimal shutdown

  Standard supervisors shut down in a fixed order, which could make shutting down queues with
  active jobs and a lengthy grace period very slow. This switches to a `DynamicSupervisor` for
  queue supervision so queues can shut down simultaneously while still respecting the grace
  period.

- [Executor] Retry acking infinitely after job execution

  After jobs execute the producer must record their status in the database. Previously, if acking
  failed due to a connection error after 10 retries it would orphan the job. Now, acking retries
  infinitely (with backoff) until the function succeeds. The result is stronger execution
  guarantees with backpressure during periods of database fragility.

- [Oban] Accept a `Job` struct as well as a job id for `cancel_job/1` and `retry_job/1`

  Now it's possible to write `Oban.cancel_job(job)` directly, rather than
  `Oban.cancel_job(job.id)`.

- [Worker] Allow snoozing jobs for zero seconds.

  Returning `{:snooze, 0}` immediately reschedules a job without any delay.

- [Notifier] Accept arbitrary channel names for notifications, e.g. "my-channel" 

- [Telemetry] Add 'detach_default_logger/0' to programmatically disable an attached logger.

- [Testing] Avoid unnecessary query for "happy path" assertion errors in `assert_enqueued/2`

- [Testing] Inspect charlists as lists in testing assertions

  Args frequently contain lists of integers like `[123]`, which was curiously displayed as `'{'`.

### Bug Fixes

- [Executor] Correctly raise "unknown worker" errors.

  Unknown workers triggered an unknown case error rather than the appropriate "unknown worker"
  runtime error.

- [Testing] Allow `assert_enqueued` with a `scheduled_at` time for `available` jobs

  The use of `Job.new` to normalize query fields would change assertions with a "scheduled_at"
  date to _only_ check scheduled, never "available"

- [Telemetry] Remove `:worker` from engine and plugin query meta.

  The `worker` isn't part of any query indexes and prevents optimal index usage.

- [Job] Correct priority type to cover default of 0

For changes prior to v2.15 see the [v2.14][prv] docs.

[opc]: https://getoban.pro/docs/pro/changelog.html
[owc]: https://getoban.pro/docs/web/changelog.html
[prv]: https://hexdocs.pm/oban/2.14.2/changelog.html
