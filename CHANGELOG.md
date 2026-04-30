# Changelog for Oban v2.22

_🌟 Looking for changes to [Oban Pro][pro]? Check the [Oban.Pro Changelog][opc] 🌟_

Adds a job querying API, migration checking in test mode, smarter notifier ping cadence, and a
handful of bug fixes around recovery and resilience.

## 📇 Job Querying

Two new functions make it easier to load jobs without hand-rolling Ecto queries.
`Oban.Job.query/1` builds a composable query from a keyword list of field filters,
and `Oban.all_jobs/2` runs any queryable through the configured repo.

For example, to fetch every `available` job for a worker with `account_id: 1`:

```elixir
[args: %{account_id: 1}, worker: MyApp.Worker, state: :available]
|> Oban.Job.query()
|> Oban.all_jobs()
```

The result is an `Ecto.Queryable`, so it composes with further `Ecto.Query` calls, and pairs
naturally with with `Oban.cancel_all_jobs/2` and `Oban.delete_all_jobs/2`:

```elixir
[state: :available, queue: :media]
|> Oban.Job.query()
|> limit(10)
|> Oban.cancel_all_jobs()
```

## 📡 Smarter Sonar Pings

Sonar, the notifier monitor, used to ping every 5 seconds from every node. That resulted in 120
messages a minute to confirm connectivity, even in a stable environment.

Pings are now status-aware and back off when the cluster is quiet. A solitary node settles to one
ping a minute. A clustered group scales the per-node interval with peer count, so aggregate
traffic stays roughly constant as the cluster grows.

There is no configuration required. When a node joins, drops, or recovers, pings snap back to the
fast cadence immediately.

## 🧪 Migration Checks at Startup

When Oban boots in a testing mode, it now verifies that the `oban_jobs` table exists and that the
migration version is current. A missing or outdated migration fails fast with an actionable
message instead of surfacing later as cryptic database errors mid-test.

For example, forgetting to run the v2.21 migration after upgrading would previously fail somewhere
deep in a test with an enum mismatch on the new `suspended` state. Now Oban refuses to start:

```
** (RuntimeError) Oban migrations are outdated. Found version 12, but version 13 is required.

    Run migrations to update:

        mix ecto.migrate
```

The check is limited to `testing` mode and geared toward catching migration requirements before
they hit production.

## v2.22.1 — 2026-04-30

### Bug Fixes

- [Repo] Conditionally reference database driver errors

  The retryable_exceptions macro previously hard-coded references to `MyXQL.Error` and
  `Postgrex.Error`, which Elixir v1.20.0.rc.2+ flags as missing module references at macro
  expansion time when the corresponding driver isn't a project dependency. The missing module
  reference could escalate into a deadlock, and compilation would halt entirely.

  Driver error lists are now resolved at compile time and only include modules that are actually
  loaded, so projects using `Postgrex` without `MyXQL` (or vice versa) compile cleanly.

- [Cron] Reject impossible combinations in cron expressions

  Cron strings whose day and month fields could never align (e.g. "0 0 30 2 *", or "0 0 31 4 *")
  parsed, but caused `next_at/2` and `last_at/2` to loop indefinitely.

  Now expressions are validated to ensure at least one day fits within the maximum length of at
  least one selected month.

- [Cron] Validate cron range bounds before expansion

  Range parts like 0-99999999 were accepted and expanded into the full integer range before the
  out-of-bounds check fired. For sufficiently large upper bounds that could stall the BEAM and
  risk OOM. The same path was reachable via the step variant 0-99999999/1 and the open-ended form
  99999999/1.

  Expression parsing now compares against the field's allowed min/max and rejects out-of-range
  values before any range is materialized.

- [Migration] Fix prefix escaping in Postgres migrations

  Switch to the standard doubled-quote escape so it works under default Postgres configuration.

  The escaped_prefix value was using `\'` to escape single quotes, which hasn't been enabled by
  default since 9.1. Under default settings, the backslash was treated literally and the quote
  terminated the string, allowing a crafted prefix to break out of the SQL literal in
  `migrated_version/1` and the notify trigger bodies.

- [Backoff] Narrow `with_retry` exit catch to :timeout

  Exits never carry a database error module atom in the first tuple
  element. Connection failures surface as raised database exceptions,
  which the rescue clause above already handles. The catch now only
  matches `:exit, {:timeout, _}`, the one shape that's actually reachable.

## v2.22.0 — 2026-04-27

### Enhancements

- [Oban] Add `Oban.all_jobs/2` and `Oban.Job.query/1`

  Introduce `Oban.Job.query/1`, a keyword-based builder that composes Ecto queryable from a small
  set of field filters. Scalar values become equality matches, lists become `IN` matches, atoms
  are coerced, and `args` or `meta` are compiled to a containment check.

  That pairs with `Oban.all_jobs/2`, a thin function that runs any queryable through the
  configured repo.

- [Oban] Verify migrations at startup in testing mode

  When Oban starts in a testing mode, it now verifies that migrations have been run and are up to
  date. This catches migration issues early in CI rather than failing with confusing database
  errors during test execution or worse, in production.

  For Postgres, the check verifies the migration version is current, while for SQLite and MySQL,
  the check verifies the `oban_jobs` table exists.

- [Sonar] Reduce ping rate with status-aware intervals

  Sonar previously pinged every 5s regardless of cluster state, which is aggressive for systems
  where nothing is changing. It now walks between a min and max interval, resetting on any status
  change and otherwise backing off toward a status driven target:

  - `:clustered` scales with peer count so aggregate traffic stays ~1 ping per `min_interval`
    regardless of cluster size
  - `:solitary` drifts to the max interval, since its only job is verifying the notifier channel
  - `:isolated` and `:unknown` stay at `min_interval` to keep recovery probes

  Stale-node pruning now uses an absolute window (default 120s) instead of a multiple of the
  current interval, and scheduled pings are jittered to avoid synchronizing nodes.

- [Repo] The Repo retry behavior is now compile-time configurable, partially for
  testing purposes, but also to allow tweaking the internal retry behavior
  based on system requirements.

- [Repo] Allow disabling `transaction/3` retries

  Pass `retry: 0` or `retry: false` to skip retries entirely, including for expected conflicts
  like deadlocks and serialization failures. This is intended for callers invoking queries like
  `Oban.insert/2` from within an existing transaction, where a retry inside a savepoint would mask
  the real error from the outer transaction.

### Bug Fixes

- [Stager] Notify queues regardless of staging success

  When `stage_jobs/3` raises a non-recoverable exception (e.g. a unique constraint violation), the
  wrapping transaction rolls back and the queue notification never fires. Pre-existing `available`
  jobs would then sit until the stager either recovered or the cluster was restarted.

  The stager now falls back to notifying queues outside the failed transaction, preferring the
  configured global path so the whole cluster is reached, and dropping to a local registry notify
  if the database itself is unreachable.

- [Testing] Include suspended jobs in test helper queries

  The query used by test helpers like `all_enqueued/0,1` now includes `suspended` jobs in addition
  to `available` and `scheduled` states.

- [Repo] Tolerate unavailable Repo modules from all operations

  In development using containers, where recompiles take several seconds, the repo module can be
  purged and not-yet-reloaded for long enough that multiple `Stager` ticks occur. Each tick may
  crash with `UndefinedFunctionError`, blowing through the supervisor's restart quota.

  The Repo now rescues `UndefinedFunctionError` alongside the existing connection errors.

- [Notifier] Fix duplicate pid accumulation in Postgres notifier

  Registering from the same process multiple times would accumulate duplicate pids in the Postgres
  notifier. Listening was deduplicated, but process registration wasn't.
