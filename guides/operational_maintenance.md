# Operational Maintenance

This guide walks you through *maintaining* a production Oban setup from an operational
perspective.

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

> #### Caveats & Guidelines {: .info}
>
> * Pruning is best-effort and performed out-of-band. This means that all limits are soft; jobs
> beyond a specified age may not be pruned immediately after jobs complete.
>
> * Pruning is only applied to jobs that are `completed`, `cancelled`, or `discarded`. It'll never
> delete a new job, a scheduled job, or a job that failed and will be retried.
