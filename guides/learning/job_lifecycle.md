# Job Lifecycle

Oban jobs follow a state machine that governs their lifecycle. Each job transitions through
distinct states from the moment it's inserted until it reaches completion or another terminal
state.

## Job States

Jobs exist in one of eight possible states:

- `suspended` — Jobs that are held and won't be processed until they are resumed
- `available` — Jobs ready to be executed
- `scheduled` — Jobs waiting for a specific time to become available for execution
- `executing` — Jobs currently running
- `retryable` — Jobs that failed but will be automatically retried
- `completed` — Jobs that finished successfully
- `cancelled` — Jobs that were purposefully stopped
- `discarded` — Jobs that exhausted all attempts and won't be retried again

![Job State Diagram](assets/oban-states.svg)

## Initial States

When you first insert a job into Oban, it enters one of two initial states:

- `available` - The default state for new jobs that should be executed immediately
- `scheduled` - When you provide a `scheduled_at` timestamp or `scheduled_in` delay

```elixir
# Job inserted as "available"
%{id: 123} |> MyApp.Worker.new() |> Oban.insert()

# Job inserted as "scheduled"
%{id: 123} |> MyApp.Worker.new(scheduled_in: 60) |> Oban.insert()
```

## Executing State

When a job becomes `available`, it waits for a queue with available capacity to claim it.

- `available → executing` - The job is claimed by a queue with available capacity and execution
  begins
- `scheduled → available → executing` - When the scheduled time arrives, the job becomes
  available and a queue may claim it

## Retry Cycle

When a job fails but hasn't reached its `max_attempts` limit, it automatically schedules a retry.
The retry cycle follows these steps:

- `executing → retryable` - The job is scheduled to run after a backoff period
- `retryable → available → executing` - The backoff period elapsed and the job can be picked up
  for another attempt

This cycle continues until it reaches a final state.

## Final States

After execution, a job will transition to one of these final states:

- `executing → completed` - The job executed successfully
- `executing → cancelled` - The job returned `{:cancel, reason}` or was manually cancelled
- `executing → discarded` - The job failed and reached its maximum retry attempts

> #### Cleaning Up Jobs {: .tip}
>
> Oban's Pruner only removes final state jobs (`completed`, `cancelled`, and `discarded`). This
> prevents your database from growing indefinitely while still providing visibility into recently
> finished jobs.

Understanding the job lifecycle helps you build more resilient systems by properly handling
failure cases, monitoring job progress, and designing appropriate retry strategies for your
specific workloads.
