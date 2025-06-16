# Periodic Jobs

Periodic jobs allow you to schedule recurring tasks that execute on a predictable schedule. Unlike
one-time scheduled jobs, periodic jobs repeat automatically without requiring you to insert new
jobs after each execution.

Oban uses a [cron plugin](`Oban.Plugins.Cron`) to manage these recurring jobs, allowing you to
define schedules using familiar cron syntax.

## Setting Up Periodic Jobs

Periodic jobs are declared in your Oban configuration as a list of tuples in one of these formats:

* `{cron_expression, worker_module}`
* `{cron_expression, worker_module, options}`

Here's an example configuration:

```elixir
config :my_app, Oban,
  repo: MyApp.Repo,
  plugins: [
    {Oban.Plugins.Cron,
     crontab: [
       {"* * * * *", MyApp.MinuteWorker},
       {"0 * * * *", MyApp.HourlyWorker, args: %{custom: "arg"}},
       {"0 0 * * *", MyApp.DailyWorker, max_attempts: 1},
       {"0 12 * * MON", MyApp.MondayWorker, queue: :scheduled, tags: ["mondays"]},
       {"@daily", MyApp.AnotherDailyWorker}
     ]}
  ]
```

In this configuration:

* `MyApp.MinuteWorker` — Runs once every minute
* `MyApp.HourlyWorker` — Runs at the first minute of every hour with custom arguments
* `MyApp.DailyWorker` — Runs at midnight every day with no retries
* `MyApp.MondayWorker` — Runs at noon every Monday in the "scheduled" queue with specific tags
* `MyApp.AnotherDailyWorker` — Runs at midnight every day using a cron alias

## How Periodic Jobs Work

The Cron plugin automatically inserts jobs according to the schedule you define. When the time
comes for a job to run, Oban:

1. Creates a new job for the specified worker
2. Adds any custom arguments you've defined
3. Enqueues the job in the appropriate queue

Jobs are always inserted by the leader node in a cluster, which prevents duplicate jobs regardless
of cluster size, restarts, or crashes.

## Cron Expressions

> #### Crontab Guru {: .tip}
>
> Cron syntax can be difficult to write and read. We recommend using a tool like
> [Crontab Guru][guru] to make sense of cron expressions and write new ones.

Standard cron expressions consist of five fields that specify when the job should run:

```
┌───────────── minute (0 - 59)
│ ┌───────────── hour (0 - 23)
│ │ ┌───────────── day of the month (1 - 31)
│ │ │ ┌───────────── month (1 - 12 or JAN-DEC)
│ │ │ │ ┌───────────── day of the week (0 - 6 or SUN-SAT)
│ │ │ │ │
│ │ │ │ │
* * * * *
```

Each field supports several notation types:

* `*` — Wildcard, matches any value (0, 1, 2, …)
* `0` — Literal, matches only the specific value (only 0)
* `*/15` — Step, matches any value that is a multiple (0, 15, 30, 45)
* `0-5` — Range, matches any value within the range (0, 1, 2, 3, 4, 5)
* `0-9/2` — Step values can be used with ranges (0, 2, 4, 6, 8)
* `1,3,5` — Comma-separated values, matches any listed value (1, 3, 5)

Each part may have multiple rules, where rules are separated by a comma. The allowed values for
each field are as follows:

| Field      | Allowed Values                               |
| ---------- | -------------------------------------------- |
| `minute`   | 0-59                                         |
| `hour`     | 0-23                                         |
| `days`     | 1-31                                         |
| `month`    | 1-12 (or aliases, `JAN`, `FEB`, `MAR`, etc.) |
| `weekdays` | 0-6 (or aliases, `SUN`, `MON`, `TUE`, etc.)  |

### Cron Extensions

Oban supports these common cron aliases for better readability:

| Expression                 | Translates To                                   |
| -------------------------- | ----------------------------------------------- |
| `@hourly`                  | `0 * * * *`                                     |
| `@daily` (or `@midnight`)  | `0 0 * * *`                                     |
| `@weekly`                  | `0 0 * * 0`                                     |
| `@monthly`                 | `0 0 1 * *`                                     |
| `@yearly` (or `@annually`) | `0 0 1 1 *`                                     |
| `@reboot`                  | Run once at boot time across the entire cluster |

### The @reboot Expression

The `@reboot` expression is special—it runs once when a node becomes the leader, rather than at a
specific time. This behavior depends on Oban's leadership system, which can cause unexpected
delays in development environments.

In development, when you shut down your application the node may not cleanly relinquish
leadership. This creates a delay before the node can become leader again on the next startup,
making it appear as though `@reboot` jobs aren't working.

To avoid this delay in development, you can use the `Global` peer instead of the default:

```elixir
# In config/dev.exs
config :my_app, Oban,
  peer: Oban.Peers.Global,
  ...
```

The `Global` peer uses Erlang's global registration, which handles development restarts more
gracefully. Keep the default peer in production for better reliability.

### Examples

### Practical Examples

Here are some specific examples to help you understand the full range of expressions:

* `0 * * * *` — The first minute of every hour
* `*/15 9-17 * * *` — Every fifteen minutes during standard business hours (9 AM to 5 PM)
* `0 0 * DEC *` — Once a day at midnight during December
* `0 7-9,16-18 * * MON-FRI` — Once an hour during morning and evening rush hours on weekdays
* `0 0 1,15 * *` — Twice monthly on the 1st and 15th at midnight
* `0 7-9,16-18 13 * FRI` — Once an hour during rush hours on Friday the 13th

For more in depth information, see the man documentation for `cron` and `crontab` in your system.

## Caveats & Guidelines

* **Timezone Considerations**: All schedules are evaluated as UTC unless a different timezone is
  provided. See `Oban.Plugins.Cron` documentation for information about configuring a timezone to
  ensure jobs run at the expected local time.

* **Dual-Purpose Workers**: Workers can be used for both regular one-time jobs _and_ scheduled
  periodic jobs, as long as they're designed to accept different arguments appropriately. This
  allows you to reuse worker logic for both scheduled and on-demand execution.

* **Overlapping Executions**: Long-running jobs may execute simultaneously if the scheduling
  interval is shorter than the time it takes to execute the job. For example, if a job scheduled to
  run every minute takes two minutes to complete, you'll have two instances running concurrently.
  Design your workers with this possibility in mind.

* **Cluster Behavior**: Only the leader node inserts periodic jobs, which prevents duplicate job
  creation in a cluster. However, any node with the appropriate queue and workers can execute the
  job once it's inserted. This leadership-based approach is particularly important for `@reboot`
  jobs—they only run when a node becomes the leader, not necessarily immediately at startup.

* **Resolution Limit**: Cron scheduling has a one-minute resolution at minimum. For more frequent
  executions, consider alternative approaches.

* **Job Options**: Remember that you can customize periodic jobs with the same options available
  for regular jobs, including queue selection, tags, and max attempts.

[cron]: https://en.wikipedia.org/wiki/Cron
[guru]: https://crontab.guru
