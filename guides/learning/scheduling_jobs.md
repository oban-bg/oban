# Scheduling Jobs

Oban provides flexible options to schedule jobs for future execution. This is useful for scenarios
like delayed notifications, periodic maintenance tasks, or scheduling work during off-peak hours.

### Schedule in Relative Time

You can **schedule** jobs to run after a specific dalay (in seconds):

```elixir
%{id: 1}
|> MyApp.SomeWorker.new(schedule_in: _seconds = 5)
|> Oban.insert()
```

This is useful for tasks that need to happen after a short delay, such as sending a follow-up
email or retrying a failed operation.

### Schedule at a Specific Time

For tasks that need to run at a precise moment, you can schedule jobs at a *specific timestamp*:

```elixir
%{id: 1}
|> MyApp.SomeWorker.new(scheduled_at: ~U[2020-12-25 19:00:00Z])
|> Oban.insert()
```

This is particularly useful for time-sensitive operations like sending birthday messages,
executing a maintenance task at off-hours, or preparing monthly reports.

## Time Zone Considerations

Scheduling in Oban is *always* done in UTC. If you're working with timestamps in different time
zones, you must convert them to UTC before scheduling:

```elixir
# Convert a datetime in a local timezone to UTC for scheduling
utc_datetime = DateTime.shift_zone!(local_datetime, "Etc/UTC")

%{id: 1}
|> MyApp.SomeWorker.new(scheduled_at: utc_datetime)
|> Oban.insert()
```

This ensures consistent behavior across different server locations and prevents daylight saving
time issues.

## How Scheduling Works

Behind the scenes, Oban stores your job in the database with the specified scheduled time. The job
remains in a "scheduled" state until that time arrives, at which point it becomes available for
execution by the appropriate worker.

Scheduled jobs don't consume worker resources until they're ready to execute, allowing you to
queue thousands of future jobs without impacting current performance.

## Distributed Scheduling

Scheduling works seamlessly across a cluster of nodes. A job scheduled on one node will execute on
whichever node has an available worker when the scheduled time arrives. See the [*Clustering*
guide](clustering.html) for more detailed information about how Oban manages jobs in a distributed
environment.
