# Scaling Applications

## Notifications

Oban uses PubSub notifications for communication between nodes, like job inserts, pausing queues,
resuming queues, and metrics for Web. The default notifier is `Oban.Notifiers.Postgres`, which
sends all messages through the database. Postgres' notifications adds up at scale because each one
requires a separate query.

If you're clustered, switch to an alternative notifier like `Oban.Notifiers.PG`. That keeps
notifications out of the db, reduces total queries, and allows larger messages. As long as you
have a functional Distributed Erlang cluster, then it’s a single line change to your Oban
config.

```diff
 config :my_app, Oban,
+  notifier: Oban.Notifiers.PG,
```

If you're not clustered, consider using [`Oban.Notifiers.Phoenix`][onp] to send notifications
through an alternative service like Redis.

[onp]: https://github.com/sorentwo/oban_notifiers_phoenix

## Triggers

Inserting jobs emits a trigger notification to let queues know there are jobs to process
immediately, without waiting up to 1s for the next polling interval. Triggers may create many
notifications for active queues.

Evaluate if you need sub-second job dispatch. Without it, jobs may wait up to 1s before running,
but that’s not a concern for busy queues since they’re constantly fetching and dispatching.

Disable triggers in your Oban configuration:

```diff
 config :my_app, Oban,
+  insert_trigger: false,
```

## Uniqueness

Frequently, people set uniqueness for jobs that don’t really need it. Not you, of course.
Before setting uniqueness, ensure the following, in a very checklist type fashion:

1. Evaluate whether it’s necessary for your workload
2. Always set a `keys` option so that uniqueness isn’t based on the full `args` or `meta`
3. Avoid setting a `period` at all if possible, use `period: :infinity` instead

If you're still committed to setting uniquness for your jobs, consider tweaking your
configuration as follows:

```diff
use Oban.Worker, unique: [
-   period: {1, :hour},
+   period: :infinity,
+   keys: [:some_key]
```

> #### 🌟 Pro Uniqueness {: .tip}
>
> Oban Pro uses an [alternative mechanism for unique jobs][uniq] that works for bulk inserts, and
> is designed for speed, correctness, scalability, and simplicity. Uniqueness is enforced and makes insertion entirely safe between processes and nodes, without the load added
> by multiple queries.

[uniq]: https://oban.pro/docs/pro/1.5.0-rc.4/Oban.Pro.Engines.Smart.html#module-enhanced-unique

## Reindexing

To stop oban_jobs indexes from taking up so much space on disk, use the
[`Oban.Plugins.Reindexer`][onp] plugin to rebuild indexes periodically. The Postgres transactional
model applies to indexes as well as tables. That leaves bloat from inserting, updating, and
deleting jobs that auto-vacuuming won’t always fix.

The reindexer rebuilds key indexes on a fixed schedule, concurrently. Concurrent rebuilds are low
impact, they don’t lock the table, and they free up space while optimizing indexes.

The [`Oban.Plugins.Reindexer`][onp] plugin is part of OSS Oban. It runs every day at midnight by
default, but it accepts a cron-style schedule and you can tweak it to run less frequently.

```diff
config :my_app, Oban,
   plugins: [
+   {Oban.Plugins.Reindexer, schedule: "@weekly"},
    …
   ]
```

## Pruning

Ensuring you are using the `Pruner` plugin, and that you prune _aggressively_. Pruning
periodically deletes `completed`, `cancelled`, and `discarded` jobs. Your application
and database will benefit from keeping the jobs table small. Aim to retain as few jobs
as necessary for uniqueness and historic introspection.

For example, to limit historic jobs to 1 day:

```diff
 config :my_app, Oban,
  plugins: [
+    {Oban.Plugins.Pruner, max_age: 1_day_in_seconds}
     …
   ]
```

The default auto vacuum settings are conservative and may fall behind on active tables. Dead
tuples accumulate until autovacuum proc comes to mark them as cleanable.

Like indexes, the MVCC system only flags rows for deletion later. Then, those rows are deleted
when the auto-vacuum runs. Autovacuum can be tweaked for the oban_jobs table alone.Tune autovacuum
for the oban_jobs table.

The exact scale factor tuning will vary based on total rows, table size, and database load.

Below is an example of the possible scale factor and threshold:

```diff
ALTER TABLE oban_jobs SET (
  autovacuum_vacuum_scale_factor = 0,
  autovacuum_vacuum_threshold = 100
)
```

> #### 🌟 Partitioning {: .tip}
>
> For _extreme_ load (tens of millions of jobs a day), Oban Pro’s [DynamicPartitioner][dynp] may
> help. It manages partitioned tables to drop older jobs without any bloat. Dropping tables
> entirely is instantaneous and leaves zero bloat. Autovacuuming each partition is faster as well.

[dynp]: https://oban.pro/docs/pro/1.5.0-rc.4/Oban.Pro.Plugins.DynamicPartitioner.html

## Pooling

Oban uses connections from your application Repo’s pool to talk to the database. When that pool
is busy, it can starve Oban of connections and you’ll see timeout errors. Likewise, if Oban is
extremely busy (as it should be), it can starve your application of connections. A good solution
for this is to set up another pool that’s exclusively for Oban’s internal use. The dedicated
pool isolates Oban’s queries from the rest of the application.

Start by defining a new `ObanRepo`:

```elixir
defmodule MyApp.ObanRepo do
   use Ecto.Repo,
     adapter: Ecto.Adapters.Postgres,
     otp_app: :my_app
end
```

Then switch the configured `repo`, and use `get_dynamic_repo` to ensure the same repo is used
within a transaction:

```diff
 config :my_app, Oban,
-  repo: MyApp.Repo,
+  repo: MyApp.ObanRepo,
+  get_dynamic_repo: fn -> if MyApp.Repo.in_transaction?(), do: MyApp.Repo, else: MyApp.ObanRepo end
   ...
```

## High Concurrency

In a busy system with high concurrency all of the record keeping after jobs run causes pool
contention, despite the individual queries being very quick. Fetching jobs uses a single query
per queue. However, acking when a job finishes takes a single connection for each job.

Improve the ratio between executing jobs and available connections by scaling up your Ecto
`pool_size` and minimizing concurrency between all queues.

```diff
config :my_app, Repo,
-  pool_size: 10,
+  pool_size: 50,
   …

 config :my_app, Oban,
   queues: [
-    events: 200,
+    events: 50,
-    emails: 100,
+    emails: 25,
   …
```

Using a dedicated pool with a known number of constant connections can also help the ratio. It’s
not necessary for most applications, but a dedicated database can help maintain predictable
performance.
