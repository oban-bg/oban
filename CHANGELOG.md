# Changelog for Oban v2.18

_🌟 Looking for changes to Web or Pro? Check the [Oban.Pro Changelog][opc] or the [Oban.Web
Changelog][owc]. 🌟_

## 🔭 Queue Shutdown Telemetry

A new queue shutdown event, `[:oban, :queue, :shutdown]`, is emitted by each queue when it
terminates. The event originates from the `watchman` process, which tracks the total ellapsed time
from when termination starts to when all jobs complete or the allotted period is exhausted.

Any jobs that take longer than the `:shutdown_grace_period` (by default 15 seconds) are brutally
killed and left as orphans. The ids of jobs left in an executing state are listed in the event's
`orphaned` meta.

This also adds `queue:shutdown` logging to the default logger. Only queues that shutdown with
orphaned jobs are logged, which makes it easier to detect orphaned jobs and which jobs were
affected:

```
[
  message: "jobs were orphaned because they didn't finish executing in the allotted time",
  queue: "alpha",
  source: "oban",
  event: "queue:shutdown",
  ellapsed: 500,
  orphaned: [101, 102, 103]
]
```

## 🚚 Distributed PostgreSQL Support

It's now possible to run Oban in distributed PostgreSQL databases such as [Yugabyte][yuga]. This
is made possible by a few simple changes to the `Basic` engine, and a new `unlogged` migration
option.

Some PostgreSQL compatible databases don't support unlogged tables. Making `oban_peers` unlogged
isn't a requirement for Oban to operate, so it can be disabled with a migration flag:

```elixir
defmodule MyApp.Repo.Migrations.AddObanTables do
  use Ecto.Migration

  def up do
    Oban.Migration.up(version: 12, unlogged: false)
  end
end
```

[yuga]: https://www.yugabyte.com/

## 🧠 Job Observability 

Job `stop` and `exception` telemetry now includes the reported memory and total reductions from
the job's process. Values are pulled with `Process.info/2` after the job executes and safely fall
back to `0` in the event the process has crashed. Reductions are a rough proxy for CPU load, and
the new measurements will make it easier to identify computationally expensive or memory hungry
jobs.

In addition, thanks to the addition of `Process.set_label` in recent Elixir versions, the worker
name is set as the job's process label. That makes it possible to identify which job is running in
a `pid` via observer or live dashboard.

## v2.18.0 — 2024-07-26

### Enhancements

- [Job] Support simple `unique: true` and `unique: false` declarations

  Uniqueness can now be enabled with `unique: true` and disabled with `unique: false` from job
  options or a worker definition. The `unique: true` option uses all the standard defaults, but
  sets the period to `:infinity` for compatibility with Oban Pro's new `simple` unique mode.

- [Cron] Remove forced uniqueness when inserting scheduled jobs.

  Using uniqueness by default prevents being able to use the Cron plugin with databases that don't
  support uniqueness because of advisory locks. Luckily, uniqueness hasn't been necessary for safe
  cron insertion since leadership was introduced and scheduling changed to top-of-the-minute
  _many_ versions ago.

- [Engine] Introduce `check_available/1` engine callback

  The `check_available/1` callback allows engines to customize the query used to find jobs in the
  `available` state. That makes it possible for alternative engines, such Oban Pro's Smart engine,
  to check for available jobs in a fraction of the time with large queues.

- [Peer] Add `Oban.Peer.get_leader/2` for checking leadership

  The `get_leader/2` function makes it possible to check which node is currently the leader
  regardless of the Peer implementation, and without having to query the database.

- [Producer] Log a warning for unhandled producer messages.

  Some messages are falling through to the catch-all `handle_info/2` clause. Previously, they were
  silently ignored and it degraded producer functionality because inactive jobs with dead pids
  were still tracked as `running` in the producer.

- [Oban] Use structured messages for most logger warnings.

  A standard structure for warning logs makes it easier to search for errors or unhandled messages
  from Oban or a particular module.

### Bug Fixes

- [Job] Include all fields in the unique section of `Job.t/0`.

  The unique spec lacked types for both `keys` and `timestamp` keys.

- [Basic] Remove `materialized` option from `fetch_jobs/3`.

  The `MATERIALIZED` clause for CTEs didn't make a meaningful difference in job fetching accuracy.
  In some situations it caused a performance regression (which is why it was removed from Pro's
  Smart engine a while ago).

[opc]: https://getoban.pro/docs/pro/changelog.html
[owc]: https://getoban.pro/docs/web/changelog.html
[prv]: https://hexdocs.pm/oban/2.17.12/changelog.html
