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
