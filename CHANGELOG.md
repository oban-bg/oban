# Changelog for Oban v2.17

_🌟 Looking for changes to Web or Pro? Check the [Oban.Pro Changelog][opc] or the [Oban.Web
Changelog][owc]. 🌟_

This release includes an optional database migration to disable triggers and relax priority
checks. See the [v2.17 upgrade guide](v2-17.html) for step-by-step instructions.

## 📟 Universal Insert Notifications

Historically, Oban used database triggers to emit a notification after a job is inserted. That
allowed jobs to execute sooner, without waiting up to a second until the next poll event. Those
triggers and subsequent notifications added some overhead to database operations bulk inserts into
the same queue, despite deduplication logic in the trigger. Even worse, trigger notifications
didn't work behind connection poolers and were restricted to the Postgres notifier.

Now insert notifications have moved out of the database and into application code, so it's
possible to disable triggers without running database migrations, and they work for _any_
notifier, not just Postgres.

Disable notifications with the `insert_trigger` option if sub-second job execution isn't important
or you'd like to reduce PubSub chatter:

```elixir
config :my_app, Oban,
  insert_trigger: false,
  ...
```

## 🧑‍🏭 Worker Conveniences

Workers received a few quality of life improvements to make defining `unique` behaviour more
expressive and intuitive.

First, it's now possible to define a job's unique period with time units like `{1, :minute}` or
`{2, :hours}`, just like a job's `:schedule_in` option:

```elixir
use Oban.Worker, unique: [period: {5, :minutes}]
```

Second, you can set the `replace` option in `use Oban.Worker` rather than in an overridden `new/2`
or as a runtime option. For example, to enable updating a job's `scheduled_at` value on unique
conflict:

```elixir
use Oban.Worker, unique: [period: 60], replace: [scheduled: [:scheduled_at]]
```

## 🐦‍🔥 Oban Phoenix Notifier

The new [`oban_notifiers_phoenix` package][onp] allows Oban to share a Phoenix application's
PubSub for notifications. In addition to centralizing PubSub communications, it opens up the
possible transports to all PubSub adapters. As Oban already provides `Postgres` and `PG`
(Distributed Erlang) notifiers, the new package primarily enables Redis notifications.

```elixir
config :my_app, Oban,
  notifier: {Oban.Notifiers.Phoenix, pubsub: MyApp.PubSub},
  ...
```

[onp]: https://github.com/sorentwo/oban_notifiers_phoenix

## 🎚️ Ten Levels of Job Priority

Job priority may now be set to values between 0 (highest) and 9 (lowest). This increases the
range from 4 to 10 possible priorities, giving applications much finer control over execution
order.

```elixir
args
|> MyApp.PrioritizedWorker.new(priority: 9)
|> Oban.insert()
```

## v2.17.4 — 2023-02-16

### Enhancements

- [Notifier] Add `Notifier.status/1` to expose cluster connectivty status for diagnostics.

  Notifier gains `status/1`, backed by an internal `Sonar` process, for access to cluster
  diagnostics. This will help identify whether the current node can communicate with other nodes
  for vital functionality such as staging jobs.

  A new `[:oban, :notifier, :switch]` telemetry event is emitted for diagnostic instrumentation
  and switch events are displayed by the default logger.

- [Stager] Use notifier status and leadership checks to switch between `global` and `local` mode.

  The sonar-backed notifier status is more accurate than the ad-hoc stager checks previously used
  to check connectivity. Now the staging mode is determined by a combination of sonar and
  leadership—isolated follower nodes will correctly switch to `:local` (polling) mode.

  The new detection mechanism prevents an infrequent and difficult to spot bug where isolated
  follower nodes wouldn't process jobs.

- [Backoff] Catch `GenServer` timeouts in `with_retry/2`.

  Backoff's `with_retry/2` function previously rescued and retried known database exceptions, and
  it didn't catch exits. Now it also catches timeout errors to accommodate synchronized `call`
  based acks like those used in Pro's Smart engine in sync mode.

- [Stager] Avoid transactions on follower nodes.

  Only the leader needs to execute a transaction while staging. This change prevents pointless
  empty transactions from each follower node every second. Now there are 60 staging transactions
  per minute across the whole cluster, rather than 60 from each node.

- [Notifier] Unify public function type signatures and accept a `name` or `conf` in all public
  functions.

- [Plugins] Always validate and build state in `start_link/1`

  Error messages and stack traces are clearer when errors come from `start_link/1` rather than
  `init/1`, and it avoids starting processes that will immediately crash.

  This also hides `child_spec/1` in all public modules to keep it out of documentation.

- [Basic] Skip taking advisory locks in testing modes.

  Advisory locks are global and apply across transactions. That can break async tests with
  overlapping unique jobs because the lock is held in a concurrent, sandboxed test.

### Bug Fixes

- [Engine] Ensure uniqueness across args when no keys are specified regardless of insertion order.

- [Basic] Force materializing the CTE when fetching jobs.

  The CTE used to prevent optimizations in the Basic engine's fetch query is only referenced once,
  which may allow the Postgres optimizer to inline it. Inlining can negate the CTE "optimization
  fence", so we force the CTE to be materialized.

- [Job] Restore default `priority` in the schema.

  A default was still set in the database, but it was erroneously removed from the Job schema.

- [Job] Fix unique typespec by unwrapping the `field` type.

## v2.17.3 — 2023-01-23

### Enhancements

- [Stager] Rescue and report staging errors with telemetry

  Staging errors from queue contention or other database issues would cause the top level stager
  process to crash. Eventually that could shut down the entire Oban supervision tree. Now we
  rescue standard database connectivity issues instead and report them as errors in telemetry.

- [Telemetry] Include result in job exception telemetry

  Returning an `{:error, reason}` tuple triggers an :exception telemetry event, but there's still
  a return value. Exception events for crashes, raises, timeouts, and kills will have a `nil`
  result value.

- [Queue] Add producer `handle_call` clause for engine `put_meta` calls.

  Previously, the only way to put meta was through a non-blocking notification to `handle_info`.

## v2.17.2 — 2023-01-11

### Enhancements

- [Oban] Support passing changeset streams to `insert_all`.

  Accepting streams makes `Oban.insert_all` more flexible and may, in some circumstances, make it
  possible to reduce memory usage for streams of large resources.

### Bug Fixes

- [Config] Validate `:repo` option without checking for `Ecto.Repo` behaviour.

  Repo wrappers that don't implement all functions of the `Ecto.Repo` behaviour are still viable and
  shouldn't be validated with a behaviour check. This changes repo validation back to the way it
  was done in older versions, by checking that it's a valid module that exports `config/0`.

- [Peer] Handle rollback during `Oban.Peers.Postgres` peer election

  Infrequently, the postgres peer election transaction returns `{:error, :rollback}`. Now that
  return value is handled to prevent a match error.

  The peer maintains its current `leader?` status on rollback—this may cause inconsistency if the
  leader encounters an error and multiple rollbacks happen in sequence. That tradeoff is
  acceptable because the situation is unlikely and less of an issue than crashing the peer.

- [Oban] Skip queue existence check for `pause_all_queues` and `resume_all_queues` when the
  `local_only` option is passed.

## v2.17.1 — 2023-12-11

### Bug Fixes

- [Validation] Restore validation helpers still used externally

  Some of the internal validation helpers are needed by external packages that can't easily change
  to schema validation. This restores those essential validation functions.

## v2.17.0 — 2023-12-08

### Enhancements

- [Oban] Add `Oban.pause_all_queues/2` and `Oban.resume_all_queues/2`.

  Pause and resume all queues with a single function call and a single notification signal, rather
  than manually looping through all queues and issuing separate calls.

- [Cron] Add non-raising `Expression.parse/2` for use in `Cron.parse/2` and shared validations.

  Multiple locations used `parse!` and converted a raised exception into an error tuple. That was
  inefficient, repetitive, and violated the common practice of avoiding exceptions for flow
  control.

- [Validation] Use schema based validation for workers, plugins, and config. 

  Validations are now simpler and more consistent, and behaviour based notifiers such as Engine,
  Repo, and Peer are more descriptive.

- [Engine] Expand telemetry meta for all engine callbacks events.

  All callbacks now include every argument in telemetry event metadata. In some situations, e.g.
  `:init`, this simplifies testing and can be used to eliminate the need to poll a supervision
  tree to see which queues started.

- [Notifier] Add `Isolated` notifier for local use and simplified testing.

  Using PG for async tests has occasional flakes due to its eventually consistent nature. In tests
  and single node systems, we don't need to broadcast messages between instances or nodes, and a
  simplified "isolated" mechanism is ideal.

- [Repo] Add `Repo.query!/4` for `Ecto.Repo` parity

- [Migration] Configure a third-party engine's migrator using the repo's `config` map.

### Bug Fixes

- [Cron] Guard against invalid cron range expressions where the left side is greater than the
  right, e.g. `SAT-FRI`.

- [Testing] Disable the `prefix` by default in generated testing helpers.

  A prefix is only necessary when it's not the standard "public" prefix, which is rarely the case
  in testing helpers. This makes it easier to use testing helpers with the `Lite` engine.

- [Testing] Remove `prefix` segment from `assert_enqueued` error messages.

  Not all engines support a prefix and the assert/refute message in testing helpers is confusing
  when the prefix is `nil`.

### Deprecations

- [Gossip] The Gossip plugin is no longer needed, and shouldn't be used, by applications running
  Oban Web v2.10 or above.

For changes prior to v2.17 see the [v2.16][prv] docs.

[opc]: https://getoban.pro/docs/pro/changelog.html
[owc]: https://getoban.pro/docs/web/changelog.html
[prv]: https://hexdocs.pm/oban/2.16.3/changelog.html
