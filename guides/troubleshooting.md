# Troubleshooting

## Jobs Stuck Executing Forever

During deployment or unexpected node restarts, jobs may be left in an `executing` state
indefinitely. We call these jobs "orphans", but orphaning isn't a bad thing. It means that the job
wasn't lost and it may be retried again when the system comes back online.

There are two mechanisms to mitigate orphans:

1. Increase the [shutdown_grace_period](Oban.html#start_link/1-twiddly-options) to allow the
   system more time to finish executing before shutdown. During shutdown each queue stops
   fetching more jobs, but executing jobs have up to the grace period to complete. The default
   value is `15000ms`, or 15 seconds.

2. Use the [Lifeline plugin](Oban.Plugins.Lifeline.html) to automatically move those jobs back to
   available so they can run again.

```elixir
config :my_app, Oban,
    plugins: [Oban.Plugins.Lifeline],
    shutdown_grace_period: :timer.seconds(60),
    ...
```

## Jobs or Plugins aren't Running

Sometimes `Cron` or `Pruner` plugins appear to stop working unexpectedly. Typically, this happens in
systems with multi-node setups where "web" nodes only enqueue jobs while "worker" nodes are
configured to run queues and plugins. Most plugins require leadership to function, so When a "web"
node becomes leader the plugins go dormant.

The solution is to disable leadership with `peer: false` on any node that doesn't run plugins:

```elixir
config :my_app, Oban, peer: false, ...
```

## No Notifications with PgBouncer

Using PgBouncer's "Transaction Pooling" setup disables all of PostgreSQL's `LISTEN` and `NOTIFY`
activity. Some functionality, such as triggering job execution, scaling queues, canceling jobs,
etc. rely on those notifications.

There are several options available to ensure functional notifications:

1. Switch to the `Oban.Notifiers.PG` notifier. This alternative notifier relies on Distributed
   Erlang and exchanges messages within a cluster. The only drawback to the PG notifier is that it
   doesn't trigger job insertion events.

2. Switch `PgBouncer` to "Session Pooling". Session pooling isn't as resource efficient as
   transaction pooling, but it retains all Postgres functionality.

3. Use a dedicated Repo that connects directly to the database, bypassing `PgBouncer`.

If none of those options work, the [Stager][stag] will switch to `local` polling mode to ensure
that queues keep processing jobs.

[stag]: Oban.Plugins.Stager.html

## Unexpectedly Re-running All Migrations

Without a version comment on the `oban_jobs` table, it will rerun all of the migrations. This can
happen when comments are stripped when restoring from a backup, most commonly during a transition
from one database to another.

The fix is to set the latest migrated version as a comment. To start, search through your previous
migrations and find the last time you ran an Oban migration. Once you've found the latest version,
e.g. `version: 10`, then you can set that as a comment on the `oban_jobs` table:

```sql
COMMENT ON TABLE public.oban_jobs IS '10'"
```

Once the comment is in place only the migrations from that version onward will
run.
