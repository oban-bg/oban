<p align="center">
  <a href="https://github.com/sorentwo/oban">
    <img alt="oban" src="https://raw.githubusercontent.com/sorentwo/oban/main/assets/oban-logotype-large.png" width="435">
  </a>
</p>

<p align="center">
  Robust job processing in Elixir, backed by modern PostgreSQL.
  Reliable, <br /> observable and loaded with <a href="#Features">enterprise grade features</a>.
</p>

<p align="center">
  <a href="https://hex.pm/packages/oban">
    <img alt="Hex Version" src="https://img.shields.io/hexpm/v/oban.svg">
  </a>
  <a href="https://hexdocs.pm/oban">
    <img alt="Hex Docs" src="http://img.shields.io/badge/hex.pm-docs-green.svg?style=flat">
  </a>
</p>
<p align="center">
  <a href="https://github.com/sorentwo/oban/actions">
    <img alt="CI Status" src="https://github.com/sorentwo/oban/workflows/ci/badge.svg">
  </a>
  <a href="https://opensource.org/licenses/Apache-2.0">
    <img alt="Apache 2 License" src="https://img.shields.io/hexpm/l/oban">
  </a>
</p>

## Table of Contents

- [Features](#features)
- [Oban Web+Pro](#oban-webpro)
- [Usage](#usage)
  - [Installation](#installation)
  - [Requirements](#requirements)
  - [Defining Workers](#defining-workers)
  - [Enqueueing Jobs](#enqueueing-jobs)
  - [Configuring Queues](#configuring-queues)
  - [Pruning Historic Jobs](#pruning-historic-jobs)
  - [Unique Jobs](#unique-jobs)
  - [Periodic Jobs](#periodic-jobs)
  - [Prioritizing Jobs](#prioritizing-jobs)
  - [Umbrella Apps](#umbrella-apps)
- [Testing](#testing)
- [Error Handling](#error-handling)
- [Instrumentation and Logging](#instrumentation-and-logging)
- [Isolation](#isolation)
- [Community](#community)
- [Contributing](#contributing)

---

_Note: This README is for the unreleased main branch, please reference the
[official documentation on hexdocs][hexdoc] for the latest stable release._

[hexdoc]: https://hexdocs.pm/oban/Oban.html

---

## Features

Oban's primary goals are **reliability**, **consistency** and **observability**.

It is fundamentally different from other background job processing tools because
_it retains job data for historic metrics and inspection_. You can leave your
application running indefinitely without worrying about jobs being lost or
orphaned due to crashes.

#### Advantages Over Other Tools

- **Fewer Dependencies** — If you are running a web app there is a _very good_
  chance that you're running on top of a [RDBMS][rdbms]. Running your job queue
  within PostgreSQL minimizes system dependencies and simplifies data backups.

- **Transactional Control** — Enqueue a job along with other database changes,
  ensuring that everything is committed or rolled back atomically.

- **Database Backups** — Jobs are stored inside of your primary database, which
  means they are backed up together with the data that they relate to.

#### Advanced Features

- **Isolated Queues** — Jobs are stored in a single table but are executed in
  distinct queues. Each queue runs in isolation, ensuring that a job in a single
  slow queue can't back up other faster queues.

- **Queue Control** — Queues can be started, stopped, paused, resumed and scaled
  independently at runtime locally or across _all_ running nodes (even in
  environments like Heroku, without distributed Erlang).

- **Resilient Queues** — Failing queries won't crash the entire supervision tree,
  instead a backoff mechanism will safely retry them again in the future.

- **Job Canceling** — Jobs can be canceled in the middle of execution regardless
  of which node they are running on. This stops the job at once and flags it as
  `cancelled`.

- **Triggered Execution** — Database triggers ensure that jobs are dispatched as
  soon as they are inserted into the database.

- **Unique Jobs** — Duplicate work can be avoided through unique job controls.
  Uniqueness can be enforced at the argument, queue, worker and even
  sub-argument level for any period of time.

- **Scheduled Jobs** — Jobs can be scheduled at any time in the future, down to
  the second.

- **Periodic (CRON) Jobs** — Automatically enqueue jobs on a cron-like schedule.
  Duplicate jobs are never enqueued, no matter how many nodes you're running.

- **Job Priority** — Prioritize jobs within a queue to run ahead of others.

- **Historic Metrics** — After a job is processed the row isn't deleted.
  Instead, the job is retained in the database to provide metrics. This allows
  users to inspect historic jobs and to see aggregate data at the job, queue or
  argument level.

- **Node Metrics** — Every queue records metrics to the database during runtime.
  These are used to monitor queue health across nodes and may be used for
  analytics.

- **Graceful Shutdown** — Queue shutdown is delayed so that slow jobs can finish
  executing before shutdown. When shutdown starts queues are paused and stop
  executing new jobs. Any jobs left running after the shutdown grace period may
  be rescued later.

- **Telemetry Integration** — Job life-cycle events are emitted via
  [Telemetry][tele] integration. This enables simple logging, error reporting
  and health checkups without plug-ins.

[rdbms]: https://en.wikipedia.org/wiki/Relational_database#RDBMS
[tele]: https://github.com/beam-telemetry/telemetry

## Oban Web+Pro

A web dashboard for managing Oban, along with an official set of extensions,
plugins, and workers are available as licensed packages:

* [🧭 Web Overview](https://getoban.pro#oban-web)
* [🌟 Pro Overview](https://getoban.pro#oban-pro)

Learn more about prices and licensing Oban Web+Pro at
[getoban.pro](https://getoban.pro).

## Usage

<!-- MDOC -->

Oban is a robust job processing library which uses PostgreSQL for storage and
coordination.

### Installation

See the [installation guide](https://hexdocs.pm/oban/installation.html) for
details on installing and configuring Oban in your application.

### Requirements

Oban requires Elixir 1.11+, Erlang 21+, and PostgreSQL 10.0+.

### Defining Workers

Worker modules do the work of processing a job. At a minimum they must define a
`perform/1` function, which is called with an `%Oban.Job{}` struct.

Note that the `args` field of the job struct will _always_ have string keys,
regardless of the key type when the job was enqueued. The `args` are stored as
`jsonb` in PostgreSQL and the serialization process automatically stringifies
all keys.

Define a worker to process jobs in the `events` queue:

```elixir
defmodule MyApp.Business do
  use Oban.Worker, queue: :events

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"id" => id} = args}) do
    model = MyApp.Repo.get(MyApp.Business.Man, id)

    case args do
      %{"in_the" => "business"} ->
        IO.inspect(model)

      %{"vote_for" => vote} ->
        IO.inspect([vote, model])

      _ ->
        IO.inspect(model)
    end

    :ok
  end
end
```

The `use` macro also accepts options to customize max attempts, priority, tags,
and uniqueness:

```elixir
defmodule MyApp.LazyBusiness do
  use Oban.Worker,
    queue: :events,
    priority: 3,
    max_attempts: 3,
    tags: ["business"],
    unique: [period: 30]

  @impl Oban.Worker
  def perform(_job) do
    # do business slowly

    :ok
  end
end
```

Successful jobs should return `:ok` or an `{:ok, value}` tuple. The value
returned from `perform/1` is used to control whether the job is treated as a
success, a failure, cancelled or deferred for retrying later.

See the `Oban.Worker` docs for more details on failure conditions and
`Oban.Telemetry` for details on job reporting.

### Enqueueing Jobs

Jobs are simply Ecto structs and are enqueued by inserting them into the
database. For convenience and consistency all workers provide a `new/2`
function that converts an args map into a job changeset suitable for insertion:

```elixir
%{id: 1, in_the: "business", of_doing: "business"}
|> MyApp.Business.new()
|> Oban.insert()
```

The worker's defaults may be overridden by passing options:

```elixir
%{id: 1, vote_for: "none of the above"}
|> MyApp.Business.new(queue: :special, max_attempts: 5)
|> Oban.insert()
```

Jobs may be scheduled at a specific datetime in the future:

```elixir
%{id: 1}
|> MyApp.Business.new(scheduled_at: ~U[2020-12-25 19:00:56.0Z])
|> Oban.insert()
```

Jobs may also be scheduled down to the second any time in the future:

```elixir
%{id: 1}
|> MyApp.Business.new(schedule_in: 5)
|> Oban.insert()
```

Unique jobs can be configured in the worker, or when the job is built:

```elixir
%{email: "brewster@example.com"}
|> MyApp.Mailer.new(unique: [period: 300, fields: [:queue, :worker])
|> Oban.insert()
```

Job priority can be specified using an integer from 0 to 3, with 0 being the
default and highest priority:

```elixir
%{id: 1}
|> MyApp.Backfiller.new(priority: 2)
|> Oban.insert()
```

Any number of tags can be added to a job dynamically, at the time it is
inserted:

```elixir
id = 1

%{id: id}
|> MyApp.OnboardMailer.new(tags: ["mailer", "record-#{id}"])
|> Oban.insert()
```

Multiple jobs can be inserted in a single transaction:

```elixir
Ecto.Multi.new()
|> Oban.insert(:b_job, MyApp.Business.new(%{id: 1}))
|> Oban.insert(:m_job, MyApp.Mailer.new(%{email: "brewser@example.com"}))
|> Repo.transaction()
```

Occasionally you may need to insert a job for a worker that exists in another
application. In that case you can use `Oban.Job.new/2` to build the changeset
manually:

```elixir
%{id: 1, user_id: 2}
|> Oban.Job.new(queue: :default, worker: OtherApp.Worker)
|> Oban.insert()
```

`Oban.insert/2,4` is the preferred way of inserting jobs as it provides some of
Oban's advanced features (i.e., unique jobs). However, you can use your
application's `Repo.insert/2` function if necessary.

See `Oban.Job.new/2` for a full list of job options.

### Configuring Queues

Queues are specified as a keyword list where the key is the name of the queue
and the value is the maximum number of concurrent jobs. The following
configuration would start four queues with concurrency ranging from 5 to 50:

```elixir
queues: [default: 10, mailers: 20, events: 50, media: 5]
```

You may also use an expanded form to configure queues with individual overrides:

```elixir
queues: [
  default: 10,
  events: [limit: 50, paused: true]
]
```

The `events` queue will now start in a paused state, which means it won't
process anything until `Oban.resume_queue/2` is called to start it.

There isn't a limit to the number of queues or how many jobs may execute
concurrently in each queue. Some additional guidelines:

#### Caveats & Guidelines

* Each queue will run as many jobs as possible concurrently, up to the
  configured limit. Make sure your system has enough resources (i.e. database
  connections) to handle the concurrent load.

* Queue limits are local (per-node), not global (per-cluster). For example,
  running a queue with a local limit of one on three separate nodes is
  effectively a global limit of three. If you require a global limit you must
  restrict the number of nodes running a particular queue.

* Only jobs in the configured queues will execute. Jobs in any other queue will
  stay in the database untouched.

* Be careful how many concurrent jobs make expensive system calls (i.e. FFMpeg,
  ImageMagick). The BEAM ensures that the system stays responsive under load,
  but those guarantees don't apply when using ports or shelling out commands.

### Pruning Historic Jobs

Job stats and queue introspection are built on keeping job rows in the database
after they have completed. This allows administrators to review completed jobs
and build informative aggregates, at the expense of storage and an unbounded
table size. To prevent the `oban_jobs` table from growing indefinitely, Oban
provides active pruning of `completed`, `cancelled` and `discarded` jobs.

By default, the `Pruner` plugin retains jobs for 60 seconds. You can configure a
longer retention period by providing a `max_age` in seconds to the `Pruner`
plugin.

```elixir
# Set the max_age for 5 minutes
config :my_app, Oban,
  plugins: [{Oban.Plugins.Pruner, max_age: 300}]
  ...
```

#### Caveats & Guidelines

* Pruning is best-effort and performed out-of-band. This means that all limits
  are soft; jobs beyond a specified age may not be pruned immediately after jobs
  complete.

* Pruning is only applied to jobs that are `completed`, `cancelled` or
  `discarded`. It'll never delete a new job, a scheduled job or a job that
  failed and will be retried.

### Unique Jobs

The unique jobs feature lets you specify constraints to prevent enqueueing
duplicate jobs.  Uniqueness is based on a combination of `args`, `queue`,
`worker`, `state` and insertion time. It is configured at the worker or job
level using the following options:

* `:period` — The number of seconds until a job is no longer considered
  duplicate. You should always specify a period, otherwise Oban will default to
  60 seconds. `:infinity` can be used to indicate the job be considered a
  duplicate as long as jobs are retained.

* `:fields` — The fields to compare when evaluating uniqueness. The available
  fields are `:args`, `:queue` and `:worker`, by default all three are used.

* `:keys` — A specific subset of the `:args` to consider when comparing against
  historic jobs. This allows a job with multiple key/value pairs in the args to
  be compared using only a subset of them.

* `:states` — The job states that are checked for duplicates. The available
  states are `:available`, `:scheduled`, `:executing`, `:retryable`,
  `:completed`, `:cancelled` and `:discarded`. By default all states except for
  `:discarded` and `:cancelled` are checked, which prevents duplicates even if
  the previous job has been completed.

For example, configure a worker to be unique across all fields and states for 60
seconds:

```elixir
use Oban.Worker, unique: [period: 60]
```

Configure the worker to be unique only by `:worker` and `:queue`:

```elixir
use Oban.Worker, unique: [fields: [:queue, :worker], period: 60]
```

Or, configure a worker to be unique until it has executed:

```elixir
use Oban.Worker, unique: [period: 300, states: [:available, :scheduled, :executing]]
```

Only consider the `:url` key rather than the entire `args`:

```elixir
use Oban.Worker, unique: [fields: [:args, :worker], keys: [:url]]
```

You can use `Oban.Job.states/0` to specify uniqueness across _all_ states,
including `:discarded`:

```elixir
use Oban.Worker, unique: [period: 300, states: Oban.Job.states()]
```

#### Detecting Unique Conflicts

When unique settings match an existing job, the return value of `Oban.insert/2`
is still `{:ok, job}`. However, you can detect a unique conflict by checking the
jobs' `:conflict?` field. If there was an existing job, the field is `true`;
otherwise it is `false`.

You can use the `:conflict?` field to customize responses after insert:

```elixir
with {:ok, %Job{conflict?: true}} <- Oban.insert(changeset) do
  {:error, :job_already_exists}
end
```

Note that conflicts are only detected for jobs enqueued through `Oban.insert/2,3`.
Jobs enqueued through `Oban.insert_all/2` _do not_ use per-job unique
configuration.

#### Replacing Values

In addition to detecting unique conflicts, passing options to `replace` can
update any job field when there is a conflict. Any of the following fields can
be replaced:  `args`, `max_attempts`, `meta`, `priority`, `queue`,
`scheduled_at`, `tags`, `worker`.

For example, to change the `priority` and increase `max_attempts` when there is
a conflict:

```elixir
BusinessWorker.new(
  args,
  max_attempts: 5,
  priority: 0,
  replace: [:max_attempts, :priority]
)
```

Another example is bumping the scheduled time on conflict. Either `scheduled_at`
or `schedule_in` values will work, but the replace option is always
`scheduled_at`.

```elixir
UrgentWorker.new(args, schedule_in: 1, replace: [:scheduled_at])
```

#### Strong Guarantees

Unique jobs are guaranteed through transactional locks and database queries:
they _do not_ rely on unique constraints in the database. This makes uniqueness
entirely configurable by application code, without the need for database
migrations.

### Periodic Jobs

Oban's `Cron` plugin registers workers a cron-like schedule and enqueues jobs
automatically. Periodic jobs are declared as a list of `{cron, worker}` or
`{cron, worker, options}` tuples:

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
* `MyApp.HourlyWorker` — Inserted at the first minute of every hour with custom args
* `MyApp.DailyWorker` — Inserted at midnight every day with no retries
* `MyApp.MondayWorker` — Inserted at noon every Monday in the "scheduled" queue
* `MyApp.AnotherDailyWorker` — Inserted at midnight every day with no retries

The crontab format respects all [standard rules][cron] and has one minute
resolution. Jobs are considered unique for most of each minute, which prevents
duplicate jobs with multiple nodes and across node restarts.

Like other jobs, recurring jobs will use the `:queue` specified by the worker
module (or `:default` if one is not specified).

#### Cron Expressions

Standard Cron expressions are composed of rules specifying the minutes, hours,
days, months and weekdays. Rules for each field are comprised of literal values,
wildcards, step values or ranges:

* `*` — Wildcard, matches any value (0, 1, 2, ...)
* `0` — Literal, matches only itself (only 0)
* `*/15` — Step, matches any value that is a multiple (0, 15, 30, 45)
* `0-5` — Range, matches any value within the range (0, 1, 2, 3, 4, 5)
* `0-9/2` - Step values can be used in conjunction with ranges (0, 2, 4, 6, 8)

Each part may have multiple rules, where rules are separated by a comma. The
allowed values for each field are as follows:

* `minute` — 0-59
* `hour` — 0-23
* `days` — 1-31
* `month` — 1-12 (or aliases, `JAN`, `FEB`, `MAR`, etc.)
* `weekdays` — 0-6 (or aliases, `SUN`, `MON`, `TUE`, etc.)

The following Cron extensions are supported:

* `@hourly` — `0 * * * *`
* `@daily` (as well as `@midnight`) — `0 0 * * *`
* `@weekly` — `0 0 * * 0`
* `@monthly` — `0 0 1 * *`
* `@yearly` (as well as `@annually`) — `0 0 1 1 *`
* `@reboot` — Run once at boot across the entire cluster

Some specific examples that demonstrate the full range of expressions:

* `0 * * * *` — The first minute of every hour
* `*/15 9-17 * * *` — Every fifteen minutes during standard business hours
* `0 0 * DEC *` — Once a day at midnight during December
* `0 7-9,4-6 13 * FRI` — Once an hour during both rush hours on Friday the 13th

For more in depth information see the man documentation for `cron` and `crontab`
in your system. Alternatively you can experiment with various expressions
online at [Crontab Guru][guru].

#### Caveats & Guidelines

* All schedules are evaluated as UTC unless a different timezone is provided.
  See `Oban.Plugins.Cron` for information about configuring a timezone.

* Workers can be used for regular _and_ scheduled jobs so long as they accept
  different arguments.

* Duplicate jobs are prevented through transactional locks and unique
  constraints. Workers that are used for regular and scheduled jobs _must not_
  specify `unique` options less than `60s`.

* Long running jobs may execute simultaneously if the scheduling interval is
  shorter than it takes to execute the job. You can prevent overlap by passing
  custom `unique` opts in the crontab config:

  ```elixir
  custom_args = %{scheduled: true}

  unique_opts = [
    period: 60 * 60 * 24,
    states: [:available, :scheduled, :executing]
  ]

  config :my_app, Oban,
    repo: MyApp.Repo,
    plugins: [
      {Oban.Plugins.Cron,
       crontab: [
         {"* * * * *", MyApp.SlowWorker, args: custom_args, unique: unique_opts}
       ]}
    ]
  ```

[cron]: https://en.wikipedia.org/wiki/Cron#Overview
[guru]: https://crontab.guru

### Prioritizing Jobs

Normally, all available jobs within a queue are executed in the order they were
scheduled. You can override the normal behavior and prioritize or de-prioritize
a job by assigning a numerical `priority`.

* Priorities from 0-3 are allowed, where 0 is the highest priority and 3 is the
  lowest.

* The default priority is 0, unless specified all jobs have an equally high
  priority.

* All jobs with a higher priority will execute before any jobs with a lower
  priority. Within a particular priority jobs are executed in their scheduled
  order.

### Umbrella Apps

If you need to run Oban from an umbrella application where more than one of
the child apps need to interact with Oban, you may need to set the `:name` for
each child application that configures Oban.

For example, your umbrella contains two apps: `MyAppA` and `MyAppB`. `MyAppA` is
responsible for inserting jobs, while only `MyAppB` actually runs any queues.

Configure Oban with a custom name for `MyAppA`:

```elixir
config :my_app_a, Oban,
  name: MyAppA.Oban,
  repo: MyApp.Repo
```

Then configure Oban for `MyAppB` with a different name:

```elixir
config :my_app_b, Oban,
  name: MyAppB.Oban,
  repo: MyApp.Repo,
  queues: [default: 10]
```

Now, use the configured name when calling functions like `Oban.insert/2`,
`Oban.insert_all/2`, `Oban.drain_queue/2`, etc., to reference the correct Oban
process for the current application.

```elixir
Oban.insert(MyAppA.Oban, MyWorker.new(%{}))
Oban.insert_all(MyAppB.Oban, multi, :multiname, [MyWorker.new(%{})])
Oban.drain_queue(MyAppB.Oban, queue: :default)
```

## Testing

Find testing setup, helpers, and strategies in the [testing guide](https://hexdocs.pm/oban/testing.html).

## Error Handling

When a job returns an error value, raises an error, or exits during execution the
details are recorded within the `errors` array on the job. When the number of
execution attempts is below the configured `max_attempts` limit, the job will
automatically be retried in the future.

The retry delay has an exponential backoff, meaning the job's second attempt
will be after 16s, third after 31s, fourth after 1m 36s, etc.

See the `Oban.Worker` documentation on "Customizing Backoff" for alternative
backoff strategies.

### Error Details

Execution errors are stored as a formatted exception along with metadata about
when the failure occurred and which attempt caused it. Each error is stored with
the following keys:

* `at` The UTC timestamp when the error occurred at
* `attempt` The attempt number when the error occurred
* `error` A formatted error message and stacktrace

See the [Instrumentation](#Instrumentation-and-Logging) docs for an example of
integrating with external error reporting systems.

### Limiting Retries

By default, jobs are retried up to 20 times. The number of retries is controlled
by the `max_attempts` value, which can be set at the Worker or Job level. For
example, to instruct a worker to discard jobs after three failures:

```elixir
use Oban.Worker, queue: :limited, max_attempts: 3
```

### Limiting Execution Time

By default, individual jobs may execute indefinitely. If this is undesirable you
may define a timeout in milliseconds with the `timeout/1` callback on your
worker module.

For example, to limit a worker's execution time to 30 seconds:

```elixir
def MyApp.Worker do
  use Oban.Worker

  @impl Oban.Worker
  def perform(_job) do
    something_that_may_take_a_long_time()

    :ok
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(30)
end
```

The `timeout/1` function accepts an `Oban.Job` struct, so you can customize the
timeout using any job attributes.

Define the `timeout` value through job args:

```elixir
def timeout(%_{args: %{"timeout" => timeout}}), do: timeout
```

Define the `timeout` based on the number of attempts:

```elixir
def timeout(%_{attempt: attempt}), do: attempt * :timer.seconds(5)
```

## Instrumentation and Logging

Oban provides integration with [Telemetry][tele], a dispatching library for
metrics. It is easy to report Oban metrics to any backend by attaching to
`:oban` events.

Here is an example of a sample unstructured log handler:

```elixir
defmodule MyApp.ObanLogger do
  require Logger

  def handle_event([:oban, :job, :start], measure, meta, _) do
    Logger.warn("[Oban] :started #{meta.worker} at #{measure.system_time}")
  end

  def handle_event([:oban, :job, event], measure, meta, _) do
    Logger.warn("[Oban] #{event} #{meta.worker} ran in #{measure.duration}")
  end
end
```

Attach the handler to success and failure events in `application.ex`:

```elixir
events = [[:oban, :job, :start], [:oban, :job, :stop], [:oban, :job, :exception]]

:telemetry.attach_many("oban-logger", events, &MyApp.ObanLogger.handle_event/4, [])
```

The `Oban.Telemetry` module provides a robust structured logger that handles all
of Oban's telemetry events. As in the example above, attach it within your
`application.ex` module:

```elixir
:ok = Oban.Telemetry.attach_default_logger()
```

For more details on the default structured logger and information on event
metadata see docs for the `Oban.Telemetry` module.

### Reporting Errors

Another great use of execution data is error reporting. Here is an example of
integrating with [Sentry][sentry] to report job failures:

```elixir
defmodule ErrorReporter do
  def handle_event([:oban, :job, :exception], measure, meta, _) do
    extra =
      meta.job
      |> Map.take([:id, :args, :meta, :queue, :worker])
      |> Map.merge(measure)

    Sentry.capture_exception(meta.reason, stacktrace: meta.stacktrace, extra: extra)
  end
end

:telemetry.attach(
  "oban-errors",
  [:oban, :job, :exception],
  &ErrorReporter.handle_event/4,
  []
)
```

You can use exception events to send error reports to Honeybadger, Rollbar,
AppSignal or any other application monitoring platform.

[tele]: https://hexdocs.pm/telemetry
[sentry]: https://sentry.io

## Isolation

Oban supports namespacing through PostgreSQL schemas, also called "prefixes" in
Ecto. With prefixes your jobs table can reside outside of your primary schema
(usually public) and you can have multiple separate job tables.

To use a prefix you first have to specify it within your migration:

```elixir
defmodule MyApp.Repo.Migrations.AddPrefixedObanJobsTable do
  use Ecto.Migration

  def up do
    Oban.Migrations.up(prefix: "private")
  end

  def down do
    Oban.Migrations.down(prefix: "private")
  end
end
```

The migration will create the "private" schema and all tables, functions and
triggers within that schema. With the database migrated you'll then specify the
prefix in your configuration:

```elixir
config :my_app, Oban,
  prefix: "private",
  repo: MyApp.Repo,
  queues: [default: 10]
```

Now all jobs are inserted and executed using the `private.oban_jobs` table. Note
that `Oban.insert/2,4` will write jobs in the `private.oban_jobs` table, you'll
need to specify a prefix manually if you insert jobs directly through a repo.

### Supervisor Isolation

Not only is the `oban_jobs` table isolated within the schema, but all
notification events are also isolated. That means that insert/update events will
only dispatch new jobs for their prefix. You can run multiple Oban instances
with different prefixes on the same system and have them entirely isolated,
provided you give each supervisor a distinct id.

Here we configure our application to start three Oban supervisors using the
"public", "special" and "private" prefixes, respectively:

```elixir
def start(_type, _args) do
  children = [
    Repo,
    Endpoint,
    {Oban, name: ObanA, repo: Repo},
    {Oban, name: ObanB, repo: Repo, prefix: "special"},
    {Oban, name: ObanC, repo: Repo, prefix: "private"}
  ]

  Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)
end
```

### Dynamic Repositories

Oban supports [Ecto dynamic repositories][dynamic] through the
`:get_dynamic_repo` option. To make this work, you need to run a separate Oban
instance per each dynamic repo instance. Most often it's worth bundling each
Oban and repo instance under the same supervisor:

```elixir
def start_repo_and_oban(instance_id) do
  children = [
    {MyDynamicRepo, name: nil, url: repo_url(instance_id)},
    {Oban, name: instance_id, get_dynamic_repo: fn -> repo_pid(instance_id) end}
  ]

  Supervisor.start_link(children, strategy: :one_for_one)
end
```

The function `repo_pid/1` must return the pid of the repo for the given
instance. You can use `Registry` to register the repo (for example in the repo's
`init/2` callback) and discover it.

If your application exclusively uses dynamic repositories and doesn't specify
all credentials upfront, you must implement an `init/1` callback in your Ecto
Repo. Doing so provides the Postgres notifier with the correct credentials on
init, allowing jobs to process as expected.

[dynamic]: https://hexdocs.pm/ecto/replicas-and-dynamic-repositories.html#dynamic-repositories

<!-- MDOC -->

## Community

There are a few places to connect and communicate with other Oban users.

- [Request an invitation][invite] and join the *#oban* channel on [Slack][slack]
- Ask questions and discuss Oban on the [Elixir Forum][forum]
- Learn about bug reports and upcoming features in the [issue tracker][issues]
- Follow @sorentwo on [Twitter][twitter]

[invite]: https://elixir-slackin.herokuapp.com/
[slack]: https://elixir-lang.slack.com/
[forum]: https://elixirforum.com/
[issues]: https://github.com/sorentwo/oban/issues
[twitter]: https://twitter.com/sorentwo

## Contributing

To run the Oban test suite you must have PostgreSQL 10+ running locally with a
database named `oban_test`. Follow these steps to create the database, create
the database and run all migrations:

```bash
mix test.setup
```

To ensure a commit passes CI you should run `mix test.ci` locally, which executes the
following commands:

* Check formatting (`mix format --check-formatted`)
* Lint with Credo (`mix credo --strict`)
* Run all tests (`mix test --raise`)
* Run Dialyzer (`mix dialyzer`)
