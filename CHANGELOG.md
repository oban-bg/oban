# Changelog for Oban v2.24

_🌟 Looking for changes to [Oban Pro][pro]? Check the [Oban.Pro Changelog][opc] 🌟_

This release unifies configuration for queues, repos, and services, swaps opaque timing integers
for readable durations, and backports per-entry cron timezones and attempt-preserving snoozes from
Oban Pro.

## ⚙️ Unified Service Configuration

Configuration for queues, repos, and all services (formerly "plugins") is now entirely unified.
This is a massive syntactic change, but it isn't all sugar. There's purpose behind the unification
and the configuration hoisting.

Functionality like pruning jobs and rescuing orphaned jobs is essential to running Oban, and it
shouldn't be an optional afterthought that's demoted as a "plugin" and buried in a guide. Now
services are top level configuration just like the `engine`, `notifier`, and `peer`:

```elixir
config :my_app, Oban,
  cron: [crontab: [{"0 2 * * *", MyApp.Nightly}]],
  pruner: [max_age: {7, :days}],
  lifeline: [rescue_after: {30, :minutes}],
  reindexer: Oban.Reindexer,
  ...
```

This configuration style should look familiar to anybody using [`oban-py`][py]. Building it is
where we realized that these services are core functionality (in fact, it doesn't even have
plugins).

Service module names are flatter as well. Since they're not considered plugins anymore, the
`Plugin` namespace was a confusing misnomer—so `Oban.Plugins.Cron` is simply `Oban.Cron`,
`Oban.Plugins.Pruner` is now `Oban.Pruner`, and so on.

Along with keyword options, the unified syntax supports bare modules, `{module, opts}` tuples, and
disabling functionality altogether by passing `false`. The tuple variant makes it especially easy
to swap core services out for alternatives (particularly useful for Pro 😉):

```diff
config :my_app, Oban,
+ engine: Oban.Pro.Engine,
- cron: {Oban.Cron, crontab: [...]},
+ cron: {Oban.Pro.Cron, crontab: [...]},
- lifeline: Oban.Lifeline,
+ lifeline: Oban.Pro.Lifeline,
- pruner: {Oban.Pruner, ...},
+ pruner: {Oban.Pro.Pruner, ...},
- queues: [...]
+ queues: {Oban.Pro.Queues, queues: [...]}
```

You'll see more about that in the Pro v1.8 release as well.

Finally, the `repo` option got the same treatment. Both `log` and `get_dynamic_repo` were really
repo options, and the stand-alone `log` option was genuinely confusing. Now you can use the tuple
format to pass those options through `:repo` directly:

```elixir
repo: {MyApp.Repo, log: false, dynamic_repo: fn -> MyApp.Repo end}
```

Don't worry, these **changes are fully backward compatible**. Oban transparently rewrites older
configuration formats into the correct format, all of the old plugin modules have backward
compatible shims, and you can still provide `plugins` beyond the standard services.

[py]: https://github.com/oban-bg/oban-py

## 🎁 Backports from Oban Pro

Two long-standing Pro features are now built into Oban. They're small quality-of-life fixes that
most people run into eventually, which makes them a better fit for core.

First, individual crontab entries may override the scheduler's timezone, so a single `Cron`
service can handle schedules in multiple zones:

```elixir
[
  {"0 7 * * *", MyApp.Strictly, timezone: "America/Chicago"},
  {"0 9 * * *", MyApp.Business, timezone: "Europe/London"}
]
```

Second, snoozing no longer consumes a job attempt. The `attempt` count is rolled back on snooze,
so backoff stays accurate across snoozes and the `max_attempts` value remains stable. Snoozing
increments a `snoozed` count in job `meta`, which helps distinguish real attempts from snoozes and
react accordingly:

```elixir
def perform(%Job{meta: %{"snoozed" => snoozed}}) when snoozed > 5 do
  {:cancel, :snoozed_too_many_times}
end
```

## ⏱️ Readable Durations

Over time, all of the Oban functions that accept durations have started to accept periods in the
`{value, unit}` tuple format as well. That convention now extends to timing options for services
like `Oban.Pruner`, so the numbers in your config are readable without mental math:

```elixir
config :my_app, Oban,
  pruner: [max_age: {7, :days}, interval: {1, :minute}],
  lifeline: [rescue_after: {30, :minutes}]
```

The format is public, centralized, and documented as `Oban.Period` now, so you can use it in
plugins and application code as well. It sports units from seconds through months, along with
helpers to convert into either seconds or milliseconds (whereas Elixir's newer `to_timeout` always
generates milliseconds, and only exists on v1.17+):

```elixir
Oban.Period.to_seconds({2, :hours})
#=> 7200

Oban.Period.to_milliseconds({5, :minutes})
#=> 300_000
```

## v2.24.0 - 2026-08-25

### Changes

- [Oban] Top-level config for maintenance plugins

  Promote the common maintenance plugins to first-class configuration keys: `cron`, `pruner`,
  `lifeline`, and `reindexer`. Each desugars into a standard plugin entry and accepts the same
  forms used elsewhere in Oban:

      config :my_app, Oban,
        cron: [crontab: [{"0 2 * * *", MyApp.Nightly}]],
        pruner: [max_age: 60 * 60 * 24 * 7]

  A keyword list configures the default plugin, and a `module` or `{module, opts}` tuple can
  configure an alternative (making it an easy switch for Oban Pro, e.g. `lifeline:
  Oban.Pro.Lifeline`).

- [Oban] Accept repo options through {repo, opts} tuple

  Configure repo-level options like logging and dynamic repo directly on the `:repo` key instead
  of at the top level:

      repo: {MyApp.Repo, log: false, dynamic_repo: fn -> MyApp.Repo end}

  The top-level `log` and `get_dynamic_repo` keys are soft-deprecated. They continue to work for
  backward compatibility, but the tuple form is now preferred and documented, keeping repo
  concerns grouped with the repo.

- [Oban] Accept a module for the top-level :queues option

  The `:queues` option now accepts a `{module, options}` tuple in addition to a static keyword list,
  which hands queue management to an alternative implementation such as Oban Pro's Queues:

      queues: {Oban.Pro.Queues, queues: [default: 10]}

  The module is started as a plugin and controls which queues run, while a static keyword list
  keeps the built-in behavior of starting the listed queues on init. Queues run regardless of the
  `:plugins` setting in either form.

  Setting `plugins: false` now disables plugins configured through top-level servic keys, e.g.
  `:cron` or `:pruner`, rather than crashing during normalization.

- [Oban] Rename maintenance plugins to top-level modules

  Plugins configured through top-level service keys now live directly in the Oban namespace:

      Oban.Plugins.Cron      -> Oban.Cron
      Oban.Plugins.Lifeline  -> Oban.Lifeline
      Oban.Plugins.Pruner    -> Oban.Pruner
      Oban.Plugins.Reindexer -> Oban.Reindexer

  The old modules are deprecated and delegate to the new ones, and legacy module names in
  `:plugins` translate to the renamed version automatically. Because the renamed module is what
  runs, plugin telemetry metadata and registry keys report the new names.

- [Oban] Expose stager as a top-level service option

  Previously staging could only be configured through the `stage_interval` option, which is
  inconsistent with other services like cron, pruner, and lifeline. The stager now accepts options
  directly, e.g. `stager: [interval: 5000]`, `false` to disable it, or `{module, opts}` tuple for
  alternative implementations.

  The `stage_interval` option is soft-deprecated but still accepted, along with the legacy
  `poll_interval` and older plugin style.

- [Queues] Rename `Oban.Midwife` to `Oban.Queues`

  Queue supervision moved from the internal `Midwife` to the public `Oban.Queues`. It takes the
  queues it starts as an option rather than reading them from the config.

  All internal queue modules moved to the `Oban.Queues.*` namespace to sit under the service that
  owns them, matching the naming style of other modules.

### Enhancements

- [Cron] Support per-entry timezones in the crontab

  Individual crontab entries may now override the plugin's timezone with a `:timezone` option,
  e.g. `{"0 9 * * *", MyApp.Worker, timezone: "America/Chicago"}`. Previously every entry was
  evaluated in a single configured timezone, which forced a separate Cron instance for each zone.

- [Worker] Roll back `attempt` and count snoozes on snooze

  Snoozing incremented `max_attempts` inflated retry timing and skewed backoff with each snooze.
  Now snoozing matches Oban Pro and the `attempt` is rolled back, so a snooze never consumes an
  attempt and backoff stays accurate. Each snooze also increments a `snoozed` count in the job's
  `meta`.

- [Job] Add `scheduled_in` for jobs and testing

  Introduce `scheduled_in` as the documented way to schedule a job for a relative time, replacing
  the awkward `scheduled_at`/`schedule_in` naming split that frequently confused people.

  The legacy `schedule_in` option is still accepted and rewritten transparently, so existing code
  continues to work.

  Testing helpers gain a matching `scheduled_in` so assertions can use a relative offset instead
  of computing an absolute `DateTime`:

      assert_enqueued worker: MyApp.Worker, scheduled_in: 3600
      assert_enqueued worker: MyApp.Worker, scheduled_in: {1, :hour}
      assert_enqueued worker: MyApp.Worker, scheduled_in: {1, :hour, delta: 10}

  The value accepts seconds, a `{amount, unit}` period tuple, and an optional `delta` for the
  timestamp comparison window.

- [Job] Restrict unique warnings to insertion states

  Workers with custom unique :states no longer warn when they omit incomplete states such as
  `:executing`. Uniqueness is only checked at insertion, so combinations of `:available`,
  `:scheduled`, and `:suspended` are valid.

  A warning is now emitted only when the configuration omits every insertion state, such as
  [:completed], which allows duplicates to go undetected. Unique period validation is also
  consolidated through `Oban.Period`.

- [Basic] Avoid starting a transaction on non-unique insert

  Refactor the engine's insert path to avoid a pointless transaction when inserting jobs, and pass
  extra options through to the `Repo.transaction/3` call when provided.

- [Lifeline] Accept period durations for `rescue_after`

  The Lifeline plugin's `rescue_after` now accepts an `Oban.Period` tuple like `{60, :minutes}` in
  addition to a raw millisecond integer, matching the duration format already used by the pruner's
  `max_age`.

- [Pruner] Accept period durations for `max_age`

  The pruner's `:max_age` now accepts a period tuple such as `{1, :day}` in addition to an integer
  count of seconds, normalized internally via `Oban.Period.to_seconds/1`.

- [Pruner] Accept period durations for plugin timing options

  Pruner and Lifeline intervals, along with Reindexer timeouts, now accept Oban.Period tuples such
  as `{30, :seconds}` in addition to millisecond integers.

- [Installer] Configure pruner and lifeline defaults

  Generated config now enables pruning and orphan rescue out of the box using the new feature
  keys, with conservative values: prune jobs after one day and rescue jobs only after two
  hours.

- [Period] Publicize duration conversion helpers

  Oban.Period is now a public API for expressing and converting durations. It provides guards for
  validating periods and functions for converting values to seconds or milliseconds:

      Oban.Period.to_seconds({2, :hours})
      Oban.Period.to_milliseconds({5, :minutes})

  Periods accept raw integers or `{value, unit}` tuples, with singular and plural units ranging from
  seconds through months. Months use a generic, non-portable 30-day window.

### Bug Fixes

- [Repo] Compile `expected_error?/1` clauses conditionally

  The MySQL clause of `expected_error?/1` raised an "unused clause" warning in environments
  without MyXQL, because the retryable error type narrows to only the loaded adapters and the
  MyXQL struct could never match.

  This moves the function into `Oban.Errors`, where the Postgres and MySQL clauses are now guarded
  alongside the existing optional error list. Each clause only compiles when its adapter is
  available, so absent adapters no longer produce a never-matched clause.

- [Notifier] Correct `listen` and `unlisten` specs with error tuples

  Without a running notifier process both `listen/2` and `unlisten/2` can return an `{:error,
  Exception.t()}` tuple rather than `:ok`.

- [Reindexer] Return :ok from checks without leadership

  Previously, on non-leader nodes the reindexer check fell through with a `nil` return, which
  telemetry reported as an error. Now the non-leader path returns `:ok`, matching all other
  plugins.

- [Telemetry] Normalize plugin telemetry metadata errors

  Plugin runs that fail, e.g. because the database is unavailable, emit a `[:oban, :plugin,
  :stop]` event with the plugin's usual metadata keys zeroed out and the underlying error added as
  :error. Previously the keys were omitted entirely, which crashed handlers that matched on them.
  That included the default logger, which telemetry then detached, silencing all Oban logging on
  the node until restart.

  The default logger now reports `:error` on `plugin:stop` events, and the `:error` value is the
  error itself rather than an `{:error, reason}` tuple.

[pro]: https://oban.pro
[opc]: https://oban.pro/docs/pro/changelog.html
