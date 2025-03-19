# Operational Maintenance

This guide walks you through *maintaining* a production Oban setup from an operational
perspective. Proper maintenance ensures your job processing system remains efficient, responsive,
and reliable over time.

## Understanding Job Persistence

Oban stores all jobs in the database, which offers several advantages:

- **Durability**: Jobs survive application restarts and crashes
- **Visibility**: Administrators can inspect job status and history
- **Accountability**: Complete audit trail of job execution
- **Analyzability**: Ability to gather statistics and metrics

However, this persistence strategy means that without proper maintenance, your job table will grow
indefinitely.

## Pruning Historic Jobs

Job stats and queue introspection are built on *keeping job rows in the database* after they have
completed. This allows administrators to review completed jobs and build informative aggregates,
at the expense of storage and an unbounded table size. To prevent the `oban_jobs` table from
growing indefinitely, Oban actively prunes `completed`, `cancelled`, and `discarded` jobs.

By default, the [pruner plugin](`Oban.Plugins.Pruner`) retains jobs for 60 seconds. You can
configure a longer retention period by providing a `:max_age` in seconds to the pruner plugin.

```elixir
config :my_app, Oban,
  plugins: [{Oban.Plugins.Pruner, max_age: _5_minutes_in_seconds = 300}],
  # ...
```

#### How Pruning Works

The pruner plugin periodically runs SQL queries to delete jobs that:

1. Are in a final state (`completed`, `cancelled`, or `discarded`)
2. Have exceeded their retention period

This happens in the background without impacting job execution.

## Indexes

Oban relies on database indexes to efficiently query and process jobs. As the `oban_jobs` table
experiences high write activity, index bloat and fragmentation can occur over time, potentially
degrading performance.

#### Understanding Oban Indexes

Oban creates several important indexes on the `oban_jobs` table:

- Indexes for efficiently fetching jobs by state and priority
- Indexes for scheduling future jobs
- Indexes for searching by queue and other attributes

With heavy usage, these indexes can become less efficient due to:

- Index bloat (where indexes contain obsolete data)
- Fragmentation (where index data is scattered across storage)

#### Using the Reindexer Plugin

Oban provides a dedicated plugin for maintaining index health: `Oban.Plugins.Reindexer`. This
plugin periodically rebuilds indexes concurrently to ensure optimal performance.

To enable automatic index maintenance, add the Reindexer to your Oban configuration:

```elixir
config :my_app, Oban,
  plugins: [Oban.Plugins.Pruner, Oban.Plugins.Reindexer],
  # ...
```

### Caveats & Guidelines

* Pruning is best-effort and performed out-of-band. This means that all limits are soft; jobs
  beyond a specified age may not be pruned immediately after jobs complete.

* Pruning is only applied to jobs that are `completed`, `cancelled`, or `discarded`. It'll never
  delete a new job, a scheduled job, or a job that failed and will be retried.

* Schedule reindexing during low-traffic periods when possible because it can be
  resource-intensive.
