# Changelog for Oban v2.23

_🌟 Looking for changes to [Oban Pro][pro]? Check the [Oban.Pro Changelog][opc] 🌟_

Sharpens resilience under database outages, catches misconfigured `unique` constraints at compile
time, and optionally scopes telemetry logging to a single instance.

## ☣️ Compile-Time Unique State Checks

Explicit `:states` lists in `unique` options have been deprecated for a while, but they still
appear in many applications. Two patterns silently break the uniqueness guarantee:

- Lists that omit insert states (`:scheduled` and `:available`) fail to deduplicate on insert, so
  duplicates slip past unconditionally.
- Partial lists like `[:available, :executing, :scheduled]` leave gaps in the lifecycle where
  duplicates land between states and break job staging.

Workers with these incomplete patterns now warn at compile time with guidance for how to repair
the misconfiguration.

## 🪵 Resilient Retry Exhaustion

Autonomous processes (`Pruner`, `Cron`) rely on transactions with a retry behavior. A database
outage that outlasts the retry time will crash the process, and trigger a restart loop that could
bring down the whole supervision tree.

The `Repo.transaction/3` function now accepts an `:on_exhausted` option that controls what happens
when retries run out. The default preserves the existing raising behavior, while `:log` writes an
error without crashing:

```elixir
Oban.Repo.transaction(conf, fun, on_exhausted: :log)
```

Internal processes that shouldn't crash on a transient outage now use `:log`, so a sustained
database hiccup is logged once rather than escalating.

## 🎯 Scoped Telemetry Logging

The telemetry backed default logger, enabled with `attach_default_logger/1`, now accepts an
`:oban_name` option to restrict logs to a single instance.

```elixir
Oban.Telemetry.attach_default_logger(oban_name: MyApp.Oban)
```

When set, multiple loggers can coexist without interleaving, and events from other instances are
dropped before they reach the log. This is primarily useful in testing, where multiple Oban
instances often run side by side and isolating the output of one of them is otherwise awkward.

## v2.23.0

### Enhancements

- [Job] Warn when unique :states leave lifecycle gaps

  Explicit `:states` lists are deprecated, but still exist in many applications. Lists that omit
  insert states like `:scheduled`, or `:available` silently fail to prevent duplicates at all.

  Partial state lists like `[:available, :executing, :scheduled]` leave gaps in the lifecycle
  where duplicates slip through or clog job staging.

  Workers defined with these patterns now warn at compile time with recommended changes for
  missing insert states or partial states.

- [Producer] Jitter producer dispatch to prevent fetch conflicts

  Producers now apply jitter to the cooldown period between fetches. Without jitter, producers
  across nodes could synchronize on shared signals and stampede the database with simultaneous
  fetches.

  The configured cooldown is now the _average_ wait rather than the _minimum_, with actual delays
  varying between roughly 1ms and 2x the configured value. For example, the default 5ms cooldown
  will range from 1ms to 10ms.

- [Oban] Tune restart intensity to tolerate queue crashes

  The top level queue supervisor used the default restart strategy, so a single misbehaving queue
  exceeding that budget could crash every other queue alongside it. This increases the budget to
  20 restarts in 60 seconds so that an isolated queue fault stays isolated for longer.

- [Producer] Replace drain polling with a pushed signal

  During queue shutdown, queues polled every 10ms until all jobs were finished. That competed for
  the producer's mailbox with the `:DOWN` messages it was waiting for and sent unnecessary
  messages. The producer now pushes a single message the moment running empties.

- [Telemetry] Optionally scope the logging to a single instance

  Add an `:oban_name` option to `attach_default_logger/1` and `detach_default_logger/1`. When set,
  multiple scoped loggers can coexist, and events from other instances are filtered out by
  matching the instance name. This is primarily useful for testing environments.

- [Repo] Add exhausted logging to `transaction/3`

  Intermittent queries ran by autonomous processes like `Pruner` would crash and enter a restart
  loop when the database was unavailable longer than the `retry` budget. Under a sustained outage
  that could be enough to crash the entire supervision tree.

  A new `:on_exhausted` retry option now accepts `:raise` (the default) and `:log`, to output an
  error log rather than raising.

### Bug Fixes

- [Config] Break extra compile cycle by deferring default modules

  Reference default modules from `Config.new/1` rather than as defstruct defaults. Inline module
  references in struct defaults created compile-time edges to modules that alias `Config`. That
  pulls 24 interconnected modules into a compile cycle.

- [Errors] Extract `Oban.Errors` to prevent circular compile cycle

  A circular chain existed between backoff -> exceptions -> job -> worker, which caused an extra
  compilation cycle.

- [Repo] Consolidate `UndefinedFunctionError` retry in `transaction/3`

  Move UndefinedFunctionError retry into `transaction/3`'s rescue alongside database errors so
  retry, backoff, and `:on_exhausted` semantics apply uniformly.

- [Repo] Retry `MyXQL` `deadlock` and `lock-wait-timeout` errors

  Treat the MyXQL error codes `1213 (deadlock)` and `1205 (lock wait timeout)` as expected
  conflicts so transactions retry on the "fast path". Previously, only Postgres conflicts
  qualified, so MySQL deadlocks fell through to the slow unexpected-error retry.

- [Cron] Skip ahead by a full day on weekday mismatch

  This is a performance enhancement for expressions that use specific weekdays. Resolution
  previously advanced by minute through every hour of every intervening day before reaching the
  next valid weekday. They now jump directly to the next matching day, making expressions like
  `*/5 * * * 1` resolve in a handful of steps instead of thousands.

- [Producer] Ignore stray `:DOWN` messages for released refs

  When a job's task finishes successfully its `ref` is demonitored, but a late `:DOWN` can still
  arrive if the message was sitting in the mailbox before demonitor ran.

  Now the down handler clause is guarded so the producer survives.

- [Migration] Tolerate non-numeric migration versions

  Custom migrators, like Oban Pro's `DynamicPartitioner`, record a comment on the `oban_jobs`
  table to indicate the version is managed externally. Parsing that as an integer crashed
  application startup during validation in testing modes.

- [Peer] Update callback arities to match actual call sites

  The `leader?` and `get_leader` callbacks were declared at arity 1, but they're always invoked as
  arity 2 with a timeout. Implementing the documented arity wasn't viable, and mocking libraries
  like Mox couldn't generate a usable mock.

  Correct the callback specs to `leader?/2` and `get_leader/2` so the behaviour matches reality.

- [Validator] Tighten fallthroughs in validation

  Each type clause now matches the success case positively and falls to an explicit error clause,
  so values that previously slipped past a negative guard and into the `:ok` catch-all are
  properly rejected.

[pro]: https://oban.pro
[opc]: https://oban.pro/docs/pro/changelog.html
