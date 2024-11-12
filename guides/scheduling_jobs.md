# Scheduling Jobs

You can **schedule** jobs down to the second any time in the future:

```elixir
%{id: 1}
|> MyApp.Business.new(schedule_in: _seconds = 5)
|> Oban.insert()
```

Jobs may also be scheduled at a *specific timestamp* in the future:

```elixir
%{id: 1}
|> MyApp.Business.new(scheduled_at: ~U[2020-12-25 19:00:56.0Z])
|> Oban.insert()
```

Scheduling is *always* in UTC. You'll have to shift timestamps in other zones to UTC before
scheduling:

```elixir
%{id: 1}
|> MyApp.Business.new(scheduled_at: DateTime.shift_zone!(datetime, "Etc/UTC"))
|> Oban.insert()
```

## Caveats & Guidelines

Usually, scheduled job management operates in **global mode** and notifies queues of available
jobs via Pub/Sub to minimize database load. However, when Pub/Sub isn't available, staging
switches to a **local mode** where each queue polls independently.

Local mode is less efficient and will only happen if you're running in an environment where
neither PostgreSQL nor PG notifications work. That situation should be rare and limited to the
following conditions:

  1. Running with a connection pooler, like [pg_bouncer], in transaction mode.
  2. Running without clustering, that is, without *distributed Erlang*.

If **both** of those criteria apply and Pub/Sub notifications won't work, then
staging will switch to polling in local mode.

[pg_bouncer]: http://www.pgbouncer.org
