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

Scheduling works across a cluster of nodes. See the [*Clustering* guide](clustering.html) for more
information.
