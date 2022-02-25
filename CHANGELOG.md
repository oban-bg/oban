# Changelog

_🌟 Looking for changes to Web or Pro? Check the [Oban.Pro Changelog][opc] or
the [Oban.Web Changelog][owc]. 🌟_

Oban v2.11 requires a v11 migration, Elixir v1.11+ and Postgres v10.0+

[Oban v2.11 Upgrade Guide][upg]

Oban v2.11 focused on reducing database load, bolstering telemetry-powered
introspection, and improving the production experience for all users. To that
end, we've extracted functionality from Oban Pro and switched to a new global
coordination model.

## Leadership

Coordination between nodes running Oban is crucial to how many plugins operate.
Staging jobs once a second from multiple nodes is wasteful, as is pruning,
rescuing, or scheduling cron jobs. Prior Oban versions used transactional
advisory locks to prevent plugins from running concurrently, but there were some
issues:

* Plugins don't know if they'll take the advisory lock, so they still need to
  run a query periodically.

* Nodes don't usually start simultaneously, and time drifts between machines.
  There's no guarantee that the top of the minute for one node is the same as
  another's—chances are, they don't match.

Oban 2.11 introduces a table-based leadership mechanism that guarantees only one
node in a cluster, where "cluster" means a bunch of nodes connected to the same
Postgres database, will run plugins. Leadership is transparent and designed for
resiliency with minimum chatter between nodes.

See the [Upgrade Guide][upg] for instructions on how to create the peers table
and get started with leadership. If you're curious about the implementation
details or want to use leadership in your application, take a look at docs for
`Oban.Peer`.

## Alternative PG (Process Groups) Notifier

Oban relies heavily on PubSub, and until now it only provided a Postgres
adapter. Postres is amazing, and has a highly performant PubSub option, but it
doesn't work in every environment (we're looking at you, PG Bouncer).

Fortunately, many Elixir applications run in a cluster connected by distributed
Erlang. That means Process Groups, aka PG, is available for many applications.

So, we pulled Oban Pro's PG notifier into Oban to make it available for
everyone! If your app runs in a proper cluster, you can switch over to the PG
notifier:

```elixir
config :my_app, Oban,
  notifier: Oban.Notifiers.PG,
  ...
```

Now there are two notifiers to choose from, each with their own strengths and
weaknesses:

* `Oban.Notifiers.Postgres` — Pros: Doesn't require distributed erlang,
  publishes `insert` events to trigger queues; Cons: Doesn't work with PGBouncer
  intransaction mode, Doesn't work in tests because of the sandbox.

* `Oban.Notifiers.PG` — Pros: Works PG Bouncer in transaction mode, Works in
  tests; Cons: Requires distributed Erlang, Doesn't publish `insert` events.

## Basic Lifeline Plugin

When a queue's producer crashes or a node shuts down before a job finishes
executing, the job may be left in an `executing` state. The worst part is that
these jobs—which we call "orphans"—are completely invisible until you go
searching through the jobs table.

Oban Pro has awlays had a "Lifeline" plugin for just this ocassion—and now we've
brought a basic `Lifeline` plugin to Oban.

To automatically rescue orphaned jobs that are still `executing`, include the
`Oban.Plugins.Lifeline` in your configuration:

```elixir
config :my_app, Oban,
  plugins: [Oban.Plugins.Lifeline],
  ...
```

Now the plugin will search and rescue orphans after they've lingered for 60
minutes.

_🌟 Note: The `Lifeline` plugin may transition jobs that are genuinely
`executing` and cause duplicate execution. For more accurate rescuing or to
rescue jobs that have exhausted retry attempts see the `DynamicLifeline` plugin
in [Oban Pro][pro]._

[pro]: https://getoban.pro

## Reindexer Plugin

Over time various Oban indexes (heck, any indexes) may grow without `VACUUM`
cleaning them up properly. When this happens, rebuilding the indexes will
release bloat and free up space in your Postgres instance.

The new `Reindexer` plugin makes index maintenance painless and automatic by
periodically rebuilding all of your Oban indexes concurrently, without any
locks.

By default, reindexing happens once a day at midnight UTC, but it's configurable
with a standard cron expression (and timezone).

```elixir
config :my_app, Oban,
  plugins: [Oban.Plugins.Reindexer],
  ...
```

See `Oban.Plugins.Reindexer` for complete options and implementation details.

## Improved Telemetry and Logging

The default telemetry backed logger includes more job fields and metadata about
execution. Most notably, the execution state and formatted error reports when
jobs fail.

Here's an example of the default output for a successful job:

```json
{
  "args":{"action":"OK","ref":1},
  "attempt":1,
  "duration":4327295,
  "event":"job:stop",
  "id":123,
  "max_attempts":20,
  "meta":{},
  "queue":"alpha",
  "queue_time":3127905,
  "source":"oban",
  "state":"success",
  "tags":[],
  "worker":"Oban.Integration.Worker"
}
```

Now, here's an sample where the job has encountered an error:

```json
{
  "attempt": 1,
  "duration": 5432,
  "error": "** (Oban.PerformError) Oban.Integration.Worker failed with {:error, \"ERROR\"}",
  "event": "job:exception",
  "state": "failure",
  "worker": "Oban.Integration.Worker"
}
```

## 2.11.2 — 2022-02-25

### Bug Fixes

- [Peer] Retain election schedule timing after a peer shuts down.

  A bug in the Peer module's "down" handler overwrote the election scheduling
  interval to `0`. As soon as the leader crashed all other peers in the cluster
  would start trying to acquire leadership as fast as possible. That caused
  excessive database load and churn.

  In addition to the interval fix, this expands the scheduling interval to 30s,
  and warns on any unknown messages to aid debugging in the future.

- [Notifier.Postgres] Prevent crashing after reconnect.

  The `handle_result` callback no longer sends an errorneous reply after a
  disconnection.

- [Job] Guard against typos and unknown options passed to `new/2`. Passing an
  unrecognized option, such as `:scheduled_in` instead of `:schedule_in`, will
  make a job invalid with a helpful base error.

  Previously, passing an unknown option was silently ignored without any warning.

## 2.11.1 — 2022-02-24

### Enhancements

- [Oban] Validate the configured `repo` by checking for `config/0`, rather than
  the more obscure `__adapter__/0` callback. This change improves integration
  with Repo wrappers such as `fly_postgres`.

- [Cron] Expose `parse/1` to facilitate testing that cron expressions are valid
  and usable in a crontab.

### Bug Fixes

- [Notifier.Postgres] Overwrite configured repo name when configuring the
  long-lived Postgres connection.

- [Lifeline] Fix rescuing when using a custom prefix. The previous
  implementation assumed that there was an `oban_jobs_state` enum in the public
  prefix.

- [Lifeline] Set `discarded_at` when discarding exhausted jobs.

## 2.11.0 — 2022-02-13

### Enhancements

- [Migration] Change the order of fields in the base index used for the primary
  Oban queries.

  The new order is much faster for frequent queries such as scheduled job
  staging. Check the v2.11 upgrade guide for instructions on swapping the
  index in existing applications.

- [Worker] Avoid spawning a separate task for workers that use timeouts.

- [Engine] Add `insert_job`, `insert_all_jobs`, `retry_job`, and
  `retry_all_jobs` as required callbacks for all engines.

- [Oban] Raise more informative error messages for missing or malformed plugins.

  Now missing plugins have a different error from invalid plugins or invalid
  options.

- [Telemetry] Normalize telemetry metadata for all engine operations:

  - Include `changeset` for `insert`
  - Include `changesets` for `insert_all`
  - Include `job` for `complete_job`, `discard_job`, etc

- [Repo] Include `[oban_conf: conf]` in `telemetry_options` for all Repo
  operations.

  With this change it's possible to differentiate between database calls made by
  Oban versus the rest of your application.

### Bug Fixes

- [Telemetry] Emit `discard` rather than `error` events when a job exhausts all retries.

  Previously `discard_job` was only called for manual discards, i.e., when a job
  returned `:discard` or `{:discard, reason}`. Discarding for exhausted attempts
  was done within `error_job` in error cases.

- [Cron] Respect the current timezone for `@reboot` jobs. Previously, `@reboot`
  expressions were evaluated on boot without the timezone applied. In that case
  the expression may not match the calculated time and jobs wouldn't trigger.

- [Cron] Delay CRON evaluation until the next minute after initialization. Now
  all cron scheduling ocurrs reliably at the top of the minute.

- [Drainer] Introduce `discard` accumulator for draining results. Now exhausted
  jobs along with manual discards count as a `discard` rather than a `failure`
  or `success`.

- [Oban] Expand changeset wrapper within multi function.

  Previously, `Oban.insert_all` could handle a list of changesets, a wrapper map
  with a `:changesets` key, or a function. However, the function had to return a
  list of changesets rather than a changeset wrapper. This was unexpected and
  made some multi's awkward.

- [Testing] Preserve `attempted_at/scheduled_at` in `perform_job/3` rather than
  overwriting them with the current time.

- [Oban] Include `false` as a viable `queue` or `plugin` option in typespecs

### Deprecations

- [Telemetry] Hard deprecate `Telemetry.span/3`, previously it was
  soft-deprecated.

### Removals

- [Telemetry] Remove circuit breaker event documentation because `:circuit`
  events aren't emitted anymore.

For changes prior to v2.11 see the [v2.10][prv] docs.

[prv]: https://hexdocs.pm/oban/2.10.1/changelog.html
[opc]: https://hexdocs.pm/oban/pro-changelog.html
[owc]: https://hexdocs.pm/oban/web-changelog.html
[upg]: https://hexdocs.pm/oban/v2-11.html
