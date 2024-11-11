# Periodic Jobs

Oban's [cron plugin](`Oban.Plugins.Cron`) registers workers that run on a cron-like schedule and enqueues jobs automatically.

Periodic jobs are declared as a list of `{cron, worker}` or `{cron, worker, options}` tuples:

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

The crontab would insert jobs as follows:

  * `MyApp.MinuteWorker` — Inserted once every minute
  * `MyApp.HourlyWorker` — Inserted at the first minute of every hour with custom arguments
  * `MyApp.DailyWorker` — Inserted at midnight every day with no retries
  * `MyApp.MondayWorker` — Inserted at noon every Monday in the "scheduled" queue
  * `MyApp.AnotherDailyWorker` — Inserted at midnight every day with no retries

The crontab format respects all [standard rules][cron] and has one minute resolution. Jobs always run at the top of the minute. All jobs get scheduled by the leader.

Like other jobs, recurring jobs will use the `:queue` specified by the worker module (or
`:default` if one is not specified).

## Cron Expressions

> #### Crontab Guru {: .tip}
>
> Cron syntax can be hard to write and read. We recommend using a tool
> like [Crontab Guru][guru] to make sense of cron expressions and write
> new ones.

Standard cron expressions are composed of rules specifying the minutes, hours, days, months and
weekdays. Rules for each field are comprised of literal values, wildcards, step values or ranges:

  * `*` — Wildcard, matches any value (0, 1, 2, …)
  * `0` — Literal, matches only itself (only 0)
  * `*/15` — Step, matches any value that is a multiple (0, 15, 30, 45)
  * `0-5` — Range, matches any value within the range (0, 1, 2, 3, 4, 5)
  * `0-9/2` — Step values can be used in conjunction with ranges (0, 2, 4, 6, 8)

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

Oban supports these common cron extensions:

| Expression                 | Translates To                                   |
| -------------------------- | ----------------------------------------------- |
| `@hourly`                  | `0 * * * *`                                     |
| `@daily` (or `@midnight`)  | `0 0 * * *`                                     |
| `@weekly`                  | `0 0 * * 0`                                     |
| `@monthly`                 | `0 0 1 * *`                                     |
| `@yearly` (or `@annually`) | `0 0 1 1 *`                                     |
| `@reboot`                  | Run once at boot time across the entire cluster |

### Examples

Here are some specific examples that demonstrate the full range of expressions:

  * `0 * * * *` — The first minute of every hour
  * `*/15 9-17 * * *` — Every fifteen minutes during standard business hours
  * `0 0 * DEC *` — Once a day at midnight during December
  * `0 7-9,4-6 13 * FRI` — Once an hour during both rush hours on Friday the 13th

For more in depth information see the man documentation for `cron` and `crontab` in your system.
Alternatively you can experiment with various expressions online at [Crontab Guru][guru].

## Caveats & Guidelines

  * All schedules are evaluated as UTC unless a different timezone is provided. See
  `Oban.Plugins.Cron` for information about configuring a timezone.

  * Workers can be used for regular _and_ scheduled jobs so long as they accept different arguments.

  * Long-running jobs may execute simultaneously if the scheduling interval is shorter than it takes
  to execute the job.

[cron]: https://en.wikipedia.org/wiki/Cron
[guru]: https://crontab.guru
