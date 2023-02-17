# Changelog for Oban v2.14

_🌟 Looking for changes to Web or Pro? Check the [Oban.Pro Changelog][opc] or
the [Oban.Web Changelog][owc]. 🌟_

Time marches on, and we minimally support Elixir 1.12+, PostgreSQL 12+, and SQLite 3.37.0+

## 🪶 SQLite3 Support with the Lite Engine

Increasingly, developers are choosing SQLite for small to medium-sized projects, not just in the
embedded space where it's had utility for many years. Many of Oban's features, such as isolated
queues, scheduling, cron, unique jobs, and observability, are valuable in smaller or embedded
environments. That's why we've added a new SQLite3 storage engine to bring Oban to smaller,
stand-alone, or embedded environments where PostgreSQL isn't ideal (or possible).

There's frighteningly little configuration needed to run with SQLite3. Migrations, queues, and
plugins all "Just Work™".

To get started, add the `ecto_sqlite3` package to your deps and configure Oban to use the
`Oban.Engines.Lite` engine:

```elixir
config :my_app, Oban,
  engine: Oban.Engines.Lite,
  queues: [default: 10],
  repo: MyApp.Repo
```

Presto! Run the migrations, include Oban in your application's supervision tree, and then start
inserting and executing jobs as normal.

⚠️ SQLite3 support is new, and while not experimental, there may be sharp edges. Please report any
issues or gaps in documentation.

## 👩‍🔬 Smarter Job Fetching

The most common cause of "jobs not processing" is when PubSub isn't available. Our troubleshooting
section instructed people to investigate their PubSub and optionally include the `Repeater`
plugin. That kind of manual remediation isn't necessary now! Instead, we automatically switch back
to local polling mode when PubSub isn't available—if it is a temporary glitch, then fetching
returns to the optimized global mode after the next health check.

Along with smarter fetching, `Stager` is no longer a plugin. It wasn't ever _really_ a plugin, as
it's core to Oban's operation, but it was treated as a plugin to simplify configuration and
testing. If you're in the minority that tweaked the staging interval, don't worry, the existing
plugin configuration is automatically translated for backward compatibility. However, if you're a
stickler for avoiding deprecated options, you can switch to the top-level `stage_interval`:

```diff
config :my_app, Oban,
  queues: [default: 10],
- plugins: [{Stager, interval: 5_000}]
+ stage_interval: 5_000
```

## 📡 Comprehensive Telemetry Data

Oban has exposed telemetry data that allows you to collect and track metrics about jobs and queues
since the very beginning. Telemetry events followed a job's lifecycle from insertion through
execution. Still, there were holes in the data—it wasn't possible to track the exact state of your
entire Oban system through telemetry data.

Now that's changed. All operations that change job state, whether inserting, deleting, scheduling,
or processing jobs report complete state-change events for _every_ job including `queue`, `state`,
and `worker` details. Even bulk operations such as `insert_all_jobs`, `cancel_all_jobs`, and
`retry_all_jobs` return a subset of fields for _all modified jobs_, rather than a simple count.

See the [2.14 upgrade guide](v2-14.html) for step-by-step instructions (all two of them).

## v2.14.2 — 2023-02-17

### Bug Fixes

- [Oban] Always disable peering with `plugins: false`. There's no reason to
  enable peering when plugins are fully disabled.

- [Notifier] Notify `Global` peers when the leader terminates.

  Now the `Global` leader sends a `down` message to all connected nodes when the
  process terminates cleanly. This behaviour prevents up to 30s of downtime
  without a leader and matches how the Postgres peer operates.

- [Notifier] Allow compiliation in a SQLite application when the `postgrex`
  package isn't available.

- [Engine] Include `jobs` in `fetch_jobs` event metadata

### Changes

- [Notifier] Pass `pid` in instead of relying on `from` for Postgres notifications.

  This prepares Oban for the upcoming `Postgrex.SimpleConnection` switch to use
  `gen_statem`.

## v2.14.1 — 2023-01-26

### Bug Fixes

- [Repo] Prevent logging SQL queries by correctly handling default opts

  The query dispatch call included opts in the args list, rather than
  separately. That passed options to `Repo.query` correctly, but it missed any
  default options such as `log: false`, which made for noisy development logs.

## v2.14.0 — 2023-01-25

### Enhancements

- [Oban] Store a `{:cancel, :shutdown}` error and emit `[:oban, :job, :stop]` telemetry when jobs
  are manually cancelled with `cancel_job/1` or `cancel_all_jobs/1`.

- [Oban] Include "did you mean" suggestions for `Oban.start_link/1` and all nested plugins when a
  similar option is available.

  ```
  Oban.start_link(rep: MyApp.Repo, queues: [default: 10])
  ** (ArgumentError) unknown option :rep, did you mean :repo?
      (oban 2.14.0-dev) lib/oban/validation.ex:46: Oban.Validation.validate!/2
      (oban 2.14.0-dev) lib/oban/config.ex:88: Oban.Config.new/1
      (oban 2.14.0-dev) lib/oban.ex:227: Oban.start_link/1
      iex:1: (file)
  ```

- [Oban] Support scoping queue actions to a particular node.

  In addition to scoping to the current node with `:local_only`, it is now possible to scope
  `pause`, `resume`, `scale`, `start`, and `stop` queues on a single node using the `:node`
  option.

  ```elixir
  Oban.scale_queue(queue: :default, node: "worker.123")
  ```

- [Oban] Remove `retry_job/1` and `retry_all_jobs/1` restriction around retrying `scheduled` jobs.

- [Job] Restrict `replace` option to specific states when unique job's have a conflict.

  ```elixir
  # Replace the scheduled time only if the job is still scheduled
  SomeWorker.new(args, replace: [scheduled: [:schedule_in]], schedule_in: 60)

  # Change the args only if the job is still available
  SomeWorker.new(args, replace: [available: [:args]])
  ```

- [Job] Introduce `format_attempt/1` helper to standardize error and attempt formatting
  across engines

- [Repo] Wrap _nearly_ all `Ecto.Repo` callbacks.

  Now every `Ecto.Repo` callback, aside from a handful that are only used to manage a `Repo`
  instance, are wrapped with code generation that omits any typespecs. Slight inconsistencies
  between the wrapper's specs and `Ecto.Repo`'s own specs caused dialyzer failures when nothing
  was genuinely broken. Furthermore, many functions were missing because it was tedious to
  manually define every wrapper function.

- [Peer] Emit telemetry events for peer leadership elections.

  Both peer modules, `Postgres` and `Global`, now emit `[:oban, :peer, :election]` events during
  leader election. The telemetry meta includes a `leader?` field for start and stop events to
  indicate if a leadership change took place.

- [Notifier] Allow passing a single channel to `listen/2` rather than a list.

- [Registry] Add `lookup/2` for conveniently fetching registered `{pid, value}` pairs.

### Bug Fixes

- [Basic] Capture `StaleEntryError` on unique replace.

  Replacing while a job is updated externally, e.g. it starts executing, could occasionally raise
  an `Ecto.StaleEntryError` within the Basic engine. Now, that exception is translated into an
  error tuple and bubbles up to the `insert` call site.

- [Job] Update `t:Oban.Job/0` to indicate timestamp fields are nullable.

### Deprecations

- [Stager] Deprecate the `Stager` plugin as it's part of the core supervision tree and may be
  configured with the top-level `stage_interval` option.

- [Repeater] Deprecate the `Repeater` plugin as it's no longer necessary with hybrid staging.

- [Migration] Rename `Migrations` to `Migration`, but continue delegating functions for backward
  compatibility.

For changes prior to v2.14 see the [v2.13][prv] docs.

[opc]: https://getoban.pro/docs/pro/changelog.html
[owc]: https://getoban.pro/docs/web/changelog.html
[prv]: https://hexdocs.pm/oban/2.13.6/changelog.html
