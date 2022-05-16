# Troubleshooting

## Jobs Stuck "Available" and Won't Execute

In multi-node setups it's possible that queues won't execute jobs as expected
and they'll be left `available`. Typically this is the result of advanced
configuration that prevents plugins from running on the leader node. Only the
leader node will run most plugins, including the `Stager` plugin that is
responsible for notifying queues that jobs are available.

There are a couple of options to fix this issue and keep jobs executing:

1. Don't use `plugins: false` in your configuration. Simply omit any `plugins`
   configuration and Oban will inject the `Stager` automatically. You can also
   set `plugins: [Oban.Plugins.Stager]` to be more explicit.

   Plugins only insert/update jobs and never execute them, leaving little reason
   to disable them altogether.

2. Set `peer: false` on any node that isn't executing plugins. That guarantees
   that plugins like `Stager` will only run on the leader node.

3. If plugins aren't disabled and leadership isn't overridden, then there's
   probably an issue with notifications. See "No Notifications with PgBouncer"
   for more tips.

## No Notifications with PgBouncer

Using PgBouncer's "Transaction Pooling" setup disables all of PostgreSQL's
`LISTEN` and `NOTIFY` activity. Some functionality, such as triggering job
execution, scaling queues, canceling jobs, etc. rely on those notifications.

There are several options available to ensure functional notifications:

1. Switch to the `Oban.Notifiers.PG` notifier. This alternative notifier relies
   on Distributed Erlang and exchanges messages within a cluster. The only
   drawback to the PG notifier is that it doesn't trigger job insertion events.

2. Switch `PgBouncer` to "Session Pooling". Session pooling isn't as resource
   efficient as transaction pooling, but it retains all Postgres functionality.

3. Use a dedicated Repo that connects directly to the database, bypassing
   `PgBouncer`.

If none of those options work, you can use the [Repeater][repe] plugin to ensure
that queues keep processing jobs:

```elixir
config :my_app, Oban,
  plugins: [Oban.Plugins.Repeater],
  ...
```

_Note: The Repeater plugin keeps jobs processing, it will not facilitate other
notification based functionality, e.g. pausing, scaling, or starting queues._

[repe]: Oban.Plugins.Repeater.html

## Unexpectedly Re-running All Migrations

Without a version comment on the `oban_jobs` table, it will rerun all of the
migrations. This can happen when comments are stripped when restoring from a
backup, most commonly during a transition from one database to another.

The fix is to set the latest migrated version as a comment. To start, search
through your previous migrations and find the last time you ran an Oban
migration. Once you've found the latest version, e.g. `version: 10`, then you
can set that as a comment on the `oban_jobs` table:

```sql
COMMENT ON TABLE public.oban_jobs IS '10'"
```

Once the comment is in place only the migrations from that version onward will
run.

## Heroku

### Elixir and Erlang Versions

If your app crashes on launch, be sure to confirm you are running the correct
version of Elixir and Erlang ([view requirements](#Requirements)). If using the
*hashnuke/elixir* buildpack, you can update the `elixir_buildpack.config` file
in your application's root directory to something like:

```
# Elixir version
elixir_version=1.13.0

# Erlang version
erlang_version=24.2
```

Available Erlang versions are available [here][versions].

[versions]: https://github.com/HashNuke/heroku-buildpack-elixir-otp-builds/blob/master/otp-versions.

### Database Connections

Make sure that you have enough available database connections when running on
Heroku. Oban uses a database connection in order to listen for Pub/Sub
notifications. This is in addition to your Ecto Repo `pool_size` setting.

Heroku's [Hobby tier Postgres plans][plans] have a maximum of 20 connections, so
if you're using one of those plan accordingly.

[plans]: https://devcenter.heroku.com/articles/heroku-postgres-plans#hobby-tier
