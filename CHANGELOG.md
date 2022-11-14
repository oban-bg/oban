# Changelog for Oban v2.13

_🌟 Looking for changes to Web or Pro? Check the [Oban.Pro Changelog][opc] or
the [Oban.Web Changelog][owc]. 🌟_

## Cancel Directly from Job Execution

Discard was initially intended to mean "a job exhausted all retries." Later, it
was added as a return type for `perform/1`, and it came to mean either "stop
retrying" or "exhausted retries" ambiguously, with no clear way to
differentiate. Even later, we introduced cancel with a `cancelled` state as a
way to stop jobs at runtime.

To repair this dichotomy, we're introducing a new `{:cancel, reason}` return
type that transitions jobs to the `cancelled` state:

```diff
case do_some_work(job) do
  {:ok, _result} = ok ->
    ok

  {:error, :invalid} ->
-   {:discard, :invalid}
+   {:cancel, :invalid}

  {:error, _reason} = error ->
    error
end
```

With this change we're also deprecating the use of discard from `perform/1`
entirely! The meaning of each action/state is now:

* `cancel`—this job was purposefully stopped from retrying, either from a return
  value or the cancel command triggered by a _human_

* `discard`—this job has exhausted all retries and transitioned by the _system_

You're encouraged to replace usage of `:discard` with `:cancel` throughout your
application's workers, but `:discard` is only soft-deprecated and undocumented
now.

## Public Engine Behaviour

Engines are responsible for all non-plugin database interaction, from inserting
through executing jobs. They're also the intermediate layer that makes Pro's
SmartEngine possible.

Along with documenting the Engine this also flattens its name for parity with
other "extension" modules. For the sake of consistency with notifiers and peers,
the Basic and Inline engines are now `Oban.Engines.Basic` and
`Oban.Engines.Inline`, respectively.

## v2.13.5 — 2022-11-14

### Bug Fixes

- [Testing] Correctly handle cancelling jobs via `:cancel` tuples when executing
  jobs with the `Inline` engine.

- [Testing] Improve the realism of `perform_job/3` by injecting a unique integer
  for the `id`, setting an `inserted_at` timestamp, and encoding/decoding `meta`
  as JSON.

- [Cron] Raise `ArgumentError` when given the wrong number of expression fields.

  Cron expressions with the wrong number of fields would raise a `MatchError`
  without any insight as to what was wrong. Now parsing returns a more helpful
  `ArgumentError` error.

## v2.13.4 — 2022-09-23

### Bug Fixes

- [Oban] Fix dialyzer ambiguity for `insert_all/2` when using a custom name
  rather than options.

- [Testing] Increment attempt when executing with `:inline` testing mode

  Inline testing mode neglected to increment the `attempt` and left it at 0.
  That caused jobs with a single attempt to erroneously report `failure` rather
  than a `discard` telemetry event.

- [Reindexer] Correct namespace reference in reindexer query.

## v2.13.3 — 2022-09-07

### Bug Fixes

- [Oban] Fix dialyzer for `insert/2` and `insert_all/2`, again.

  The recent addition of a `@spec` for `Oban.insert/2` broke dialyzer in some
  situations. To prevent this regression in the future we now include a compiled
  module that exercises all `Oban.insert` function clauses for dialyzer.

## v2.13.2 — 2022-08-19

### Bug Fixes

- [Oban] Fix `insert/3` and `insert_all/3` when using options.

  Multiple default arguments caused a conflict for function calls with options
  but without an Oban instance name, e.g. `Oban.insert(changeset, timeout: 500)`

- [Reindexer] Fix the unused index repair query and correctly report errors.

  Reindexing and deindexing would faily silently because the results weren't
  checked and no exceptions were raised.

## v2.13.1 — 2022-08-09

### Bug Fixes

- [Oban] Expand `insert`/`insert_all` typespecs for multi arity

  This fixes dialyzer issues from the introduction of `opts` to `Oban.insert` and
  `Oban.insert_all` functions.

- [Reindexer] Allow specifying timeouts for all queries

  In some cases, applying `REINDEX INDEX CONCURRENTLY` on the indexes
  `oban_jobs_args_index`, and `oban_jobs_meta_index` takes more than the default
  value (15 seconds). This new option allows clients to specify other values
  than the default.

## v2.13.0 — 2022-07-22

### Enhancements

- [Telemetry] Add `encode` option to make JSON encoding for `attach_default_logger/1`.

  Now it's possible to use the default logger in applications that prefer
  structured logging or use a standard JSON log formatter.

- [Oban] Accept a `DateTime` for the `:with_scheduled` option when draining.

   When a `DateTime` is provided, drains all jobs scheduled up to, and
   including, that point in time.

- [Oban] Accept extra options for `insert/2,4` and `insert_all/2,4`.

  These are typically the Ecto's standard "Shared Options" such as `log` and
  `timeout`. Other engines, such as Pro's `SmartEngine` may support additional
  options.

- [Repo] Add `aggregate/4` wrapper to facilitate aggregates from plugins or
  other extensions that use `Oban.Repo`.

### Bug Fixes

- [Oban] Prevent empty maps from matching non-empty maps during uniqueness checks.

- [Oban] Handle discarded and exhausted states for inline testing mode.

  Previously, returning a `:discard` tuple or exhausting attempts would cause an
  error.

- [Peer] Default `leader?` check to false on peer timeout.

  Timeouts should be rare, as they're symptoms of application/database overload.
  If leadership can't be established it's safe to assume an instance isn't
  leader and log a warning.

- [Peer] Use node-specific lock requester id for Global peers.

  Occasionally a peer module may hang while establishing leadership. In this
  case the peer isn't yet a leader, and we can fallback to `false`.

- [Config] Validate options only after applying normalizations.

- [Migrations] Allow any viable `prefix` in migrations.

- [Reindexer] Drop invalid Oban indexes before reindexing again.

  Table contention that occurs during concurrent reindexing may leave indexes in
  an invalid, and unusable state. Those indexes aren't used by Postgres and they
  take up disk space. Now the Reindexer will drop any invalid indexes before
  attempting to reindex.

- [Reindexer] Only rebuild `args` and `meta` GIN indexes concurrently.

  The new `indexes` option can be used to override the reindexed indexes rather
  than the defaults.

  The other two standard indexes (primary key and compound fields) are BTREE
  based and not as subject to bloat.

- [Testing] Fix testing mode for `perform_job` and alt engines, e.g. Inline

  A couple of changes enabled this compound fix:

  1. Removing the engine override within config and exposing a centralized
     engine lookup instead.
  2. Controlling post-execution db interaction with a new `ack` option for
     the Executor module.

### Deprecations

- [Oban] Soft replace discard with cancel return value (#730) [Parker Selbert]

For changes prior to v2.13 see the [v2.12][prv] docs.

[opc]: https://getoban.pro/docs/pro/changelog.html
[owc]: https://getoban.pro/docs/web/changelog.html
[prv]: https://hexdocs.pm/oban/2.12.1/changelog.html
