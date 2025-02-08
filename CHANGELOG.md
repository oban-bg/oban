# Changelog for Oban v2.19

_🌟 Looking for changes to [Oban Pro][pro]? Check the [Oban.Pro Changelog][opc] 🌟_

The minimum Elixir version is now v1.15. The official policy is to only support the three latest
versions of Elixir.

## 🐬 MySQL Support

Oban officially supports MySQL with the new `Dolphin` engine. Oban supports modern (read "with
full JSON support") MySQL [versions from 8.4][m84] on, and has been tested on the highly scalable
[Planetscale][pla] database.

Running on MySQL is as simple as specifying the `Dolphin` engine in your configuration:

```elixir
config :my_app, Oban,
  engine: Oban.Engines.Dolphin,
  queues: [default: 10],
  repo: MyApp.Repo
```

With this addition, Oban can run in [estimated 10% more][myx] Elixir applications!

[m84]: https://dev.mysql.com/doc/relnotes/mysql/8.4/en/
[pla]: https://planetscale.com/
[myx]: https://hex.pm/packages/myxql

## ⚗️ Automated Installer

Installing Oban into a new application is simplified with a new [igniter][ign] powered `mix` task.
The new `oban.install` task handles installing and configuring a standard Oban installation, and
it will deduce the correct `engine` and `notifier` automatically based on the database adapter.

```bash
mix igniter.install oban
```

This `oban.install` task is currently the [recommended way to install][ins] Oban. As a bonus, the
task composes together with other igniter installers, making it possible to install `phoenix`,
`ash`, `oban`, and other packages with a single command:

```bash
mix igniter.install phoenix ash_phoenix ash_postgres ash_oban
```

Look at the [`Mix.Oban.Install`][mio] docs for full usage and options.

[ign]: https://hexdocs.pm/igniter/readme.html
[ins]: installation.html
[mio]: Mix.Tasks.Oban.Install.html

## 📔 Logging Enhancements

Logging in a busy system may be noisy due to job events, but there are other events that are
particularly useful for diagnosing issues. A new `events` option for `attach_default_logger/1`
allows selective event logging, so it's possible to receive important notices such as notifier
connectivity issues, without logging all job activity:

```elixir
Oban.Telemetry.attach_default_logger(events: ~w(notifier peer stager)a)
```

Along with filtering, there are new events to make diagnosing operational problems easier.

A `peer:election` events logs leadership changes to indicate when nodes gain or lose leadership.
Leadership issues are rare, but insidious, and make diagnosing production problems especially
tricky.

```elixir
[
  message: "peer became leader",
  source: "oban",
  event: "peer:election",
  node: "worker.1",
  leader: true,
  was_leader: false
]
```

Helpfully, `plugin:stop` events are now logged for all core plugins via an optional callback, and
`plugin:exception` events are logged for all plugins regardless of whether they implement the
callback. Runtime information is logged for `Cron`, `Lifeline`, `Pruner`, `Stager`, and
`Reindexer` plugins.

For example, every time `Cron` runs successfully it will output details about the execution time
and all of the inserted job ids:

```elixir
[
  source: "oban",
  duration: 103,
  event: "plugin:stop",
  plugin: "Oban.Plugins.Cron",
  jobs: [1, 2, 3]
]
```

## ⛵️ Official JSON

Oban will default to using the official `JSON` module built into Elixir v1.18+ when available.

A new `Oban.JSON` module detects whether the official Elixir `JSON` module is available at compile
time. If it isn't available, then it falls back to `Jason`, and if `Jason` isn't available (which
is extremely rare) then it warns about a missing module.

This approach was chosen over a config option for backward compatibility because Oban will only
support the JSON module once the minimum supported Elixir version is v1.18.

## v2.19.1 — 2025-01-27

### Bug Fixes

- [Mix] Improve igniter installer idempotency and compatibility.

  The installer now uses `on_exists: :skip` when generating a migration, so it composes safely
  with other igniter installers. It also removes unnecessary `add_dep` calls that would overwrite
  a previously specified Oban version with `~> 2.18`.

## v2.19.0 — 2025-01-16

### Enhancements

- [Oban] Start all queues in parallel on initialization.

  The midwife now starts queues using an async stream to parallelize startup and minimize boot
  time for applications with many queues.

- [Oban] Safely return `nil` from `check_queue/2` when checking queues that aren't running.

  Checking on a queue that wasn't currently running on the local node now returns `nil` rather
  than causing a crash. This makes it safer to check the whether a queue is running at all without
  a `try/catch` clause.

- [Oban] Add `check_all_queues/1` to gather all queue status in a single function.

  This new helper gathers the "check" details from all running queues on the local node. While it
  was previously possible to pull the queues list from config and call `check_queue/2` on each
  entry, this more accurately pulls from the registry and checks each producer concurrently.

- [Oban] Add `delete_job/2` and `delete_all_jobs/2` operations.

  This adds `Oban.delete_job/2`, `Oban.delete_all_jobs/2`, Engine callbacks, and associated
  operations for all native engines. Deleting jobs is now easier and safer, due to automatic state
  protections.

- [Engine] Record when a queue starts shutting down

  Queue producer metadata now includes a `shutdown_started_at` field to indicate that a queue
  isn't just paused, but is actually shutting down as well.

- [Engine] Add `rescue_jobs/3` callback for all engines.

  The `Lifeline` plugin formerly used two queries to rescue jobs—one to mark jobs with remaining
  attempts as `available` and another that `discarded` the remaining stuck jobs. Those are now
  combined into a single callback, with the base definition in the `Basic` engine.

  MySQL won't accept a select in an update statement. The Dolphin implementation of
  `rescue_jobs/3` uses multiple queries to return the relevant telemetry data and make multiple
  updates.

- [Cron] Introduce `Oban.Cron` with `schedule_interval/4`

  The new `Cron` module allows processes, namely plugins, to get cron-like scheduled functionality
  with a single function call. This will allow plugins to removes boilerplate around parsing,
  scheduling, and evaluating for cron behavior.

- [Registry] Add `select/1 ` to simplify querying for registered modules.

- [Testing] Add `build_job/3` helper for easier testing.

  Extract the mechanism for verifying and building jobs out of `perform_job/3` so that it's usable
  in isolation. This also introduces `perform_job/2` for executing built jobs.

- [Telemetry] Add information on leadership changes to `oban.peer.election` event.

  An additional `was_leader?` field is included in `[:oban, :peer, :election | _]` event metadata
  to make hooking into leadership change events simpler.

- [Telemetry] Add callback powered logging for plugin events.

  Events are now logged for plugins that implement the a new optional callback, and exceptions are
  logged for all plugins regardless of whether they implement the callback.

  This adds logging for `Cron`, `Lifeline`, `Pruner`, `Stager`, and `Reindexer`.

- [Telemetry] Add peer election logging to default logger.

  The default logger now includes leadership events to make identifying the leader, and leadership
  changes between nodes, easier.

- [Telemetry] Add option to restrict logging to certain events.

  Logging in a busy system may be noisy due to job events, but there are other events that are
  particularly useful for diagnosing issues. This adds an `events` option to
  `attach_default_logger/1` to allow selective event logging.

- [Telemetry] Expose `default_handler_id/0` for telemetry testing.

  Simplifies testing whether the default logger is attached or detached in application code.

### Chores

- [Peer] The default database-backed peer was renamed from `Postgres` to `Database` because it is
  also used for MySQL databases.

### Bug Fixes

- [Oban] Allow overwriting all `insert/*` functions arities after `use Oban`.

- [Node] Correctly handle `:node` option for `scale_queue/2`

  Scoping `scale_queue/2` calls to a single node didn't work as advertised due to some extra
  validation for producer meta compatibility.

- [Migration] Fix version query for databases with non-unique `oid`

  Use `pg_catalog.obj_description(object_oid, catalog_name)`, introduced in PostgreSQL 7.2, to
  specify the `pg_class` catalog so only the `oban_jobs` description is returned.

- [Pruner] Use state specific fields when querying for prunable jobs.

  Using `scheduled_at` is not correct in all situations. Depending on job state,  one of
  `cancelled_at`, `discarded_at`, or `scheduled_at` should be used.

- [Peer] Conditionally return the current node as leader for isolated peers.

  Prevents returning the current node name when leadership is disabled.

- [Testing] Retain time as microseconds for `scheduled_at` tests.

  Include microseconds in the `begin` and `until` times used for scheduled_at tests with a delta.
  The prior version would truncate, which rounded the `until` down and broke microsecond level
  checks.

- [Telemetry] Correct spelling of "elapsed" in `oban.queue.shutdown` metadata.

[pro]: https://oban.pro
[opc]: https://oban.pro/docs/pro/changelog.html
