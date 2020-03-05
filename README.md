<p align="center">
  <a href="https://github.com/sorentwo/oban">
    <img alt="oban" src="https://raw.githubusercontent.com/sorentwo/oban/master/logotype.png" width="435">
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

- [Features](#Features)
- [Requirements](#Requirements)
- [Oban Web UI](#Oban-Web-UI)
- [Installation](#Installation)
- [Usage](#Usage)
  - [Configuring Queues](#Configuring-Queues)
  - [Defining Workers](#Defining-Workers)
  - [Enqueuing Jobs](#Enqueueing-Jobs)
  - [Pruning Historic Jobs](#Pruning-Historic-Jobs)
  - [Unique Jobs](#Unique-Jobs)
  - [Periodic Jobs](#Periodic-Jobs)
  - [Prioritizing Jobs](#Prioritizing-Jobs)
- [Testing](#Testing)
- [Error Handling](#Error-Handling)
- [Instrumentation & Logging](#Instrumentation-and-Logging)
- [Isolation](#Isolation)
- [Pulse Tracking](#Pulse-Tracking)
- [Troubleshooting](#Troubleshooting)
- [Community](#Community)
- [Contributing](#Contributing)

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
  independently at runtime across _all_ running nodes (even in environments like
  Heroku, without distributed Erlang).

- **Resilient Queues** — Failing queries won't crash the entire supervision tree,
  instead they trip a circuit breaker and will be retried again in the future.

- **Job Killing** — Jobs can be killed in the middle of execution regardless of
  which node they are running on. This stops the job at once and flags it as
  `discarded`.

- **Triggered Execution** — Database triggers ensure that jobs are dispatched as
  soon as they are inserted into the database.

- **Unique Jobs** — Duplicate work can be avoided through unique job controls.
  Uniqueness can be enforced at the argument, queue and worker level for any
  period of time.

- **Scheduled Jobs** — Jobs can be scheduled at any time in the future, down to
  the second.

- **Periodic (CRON) Jobs** — Automatically enqueue jobs on a cron-like schedule.
  Duplicate jobs are never enqueued, no matter how many nodes you're running.

- **Job Priority** — Prioritize jobs within a queue to run ahead of others.

- **Job Safety** — When a process crashes or the BEAM is terminated executing
  jobs aren't lost—they are quickly recovered by other running nodes or
  immediately when the node is restarted.

- **Historic Metrics** — After a job is processed the row is _not_ deleted.
  Instead, the job is retained in the database to provide metrics. This allows
  users to inspect historic jobs and to see aggregate data at the job, queue or
  argument level.

- **Node Metrics** — Every queue records metrics to the database during runtime.
  These are used to monitor queue health across nodes and may be used for
  analytics.

- **Queue Draining** — Queue shutdown is delayed so that slow jobs can finish
  executing before shutdown. When shutdown starts queues are paused and stop
  executing new jobs. Any jobs left running after the shutdown grace period may
  be rescued later.

- **Telemetry Integration** — Job life-cycle events are emitted via
  [Telemetry][tele] integration. This enables simple logging, error reporting
  and health checkups without plug-ins.

[rdbms]: https://en.wikipedia.org/wiki/Relational_database#RDBMS
[tele]: https://github.com/beam-telemetry/telemetry

## Requirements

Oban has been developed and actively tested with Elixir 1.8+, Erlang/OTP 21.1+
and PostgreSQL 11.0+. Running Oban currently requires Elixir 1.8+, Erlang 21+,
and PostgreSQL 9.6+.

## Oban Web UI

A web-based user interface for monitoring and managing Oban is available as a
private beta. Learn more about it and register for the beta at [oban.dev][odev].

[odev]: https://oban.dev

## Installation

Oban is published on [Hex](https://hex.pm/packages/oban). Add it to your list of
dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:oban, "~> 1.2"}
  ]
end
```

Then run `mix deps.get` to install Oban and its dependencies, including
[Ecto][ecto], [Jason][jason] and [Postgrex][postgrex].

After the packages are installed you must create a database migration to
add the `oban_jobs` table to your database:

```bash
mix ecto.gen.migration add_oban_jobs_table
```

Open the generated migration in your editor and call the `up` and `down`
functions on `Oban.Migrations`:

```elixir
defmodule MyApp.Repo.Migrations.AddObanJobsTable do
  use Ecto.Migration

  def up do
    Oban.Migrations.up()
  end

  # We specify `version: 1` in `down`, ensuring that we'll roll all the way back down if
  # necessary, regardless of which version we've migrated `up` to.
  def down do
    Oban.Migrations.down(version: 1)
  end
end
```

This will run all of Oban's versioned migrations for your database. Migrations
between versions are idempotent and will _never_ change after a release. As new
versions are released you may need to run additional migrations.

Now, run the migration to create the table:

```bash
mix ecto.migrate
```

Next see [Usage](#Usage) for how to integrate Oban into your application and
start defining jobs!

[ecto]: https://hex.pm/packages/ecto
[jason]: https://hex.pm/packages/jason
[postgrex]: https://hex.pm/packages/postgrex

#### Note About Releases

If you are using releases you may see Postgrex errors logged during your initial
deploy (or any deploy requiring an Oban migration). The errors are only
temporary! After the migration has completed each queue will start producing
jobs normally.

## Usage

<!-- MDOC -->

Oban is a robust job processing library which uses PostgreSQL for storage and
coordination.

Each Oban instance is a supervision tree and _not an application_. That means it
won't be started automatically and must be included in your application's
supervision tree. All of your configuration is passed into the supervisor,
allowing you to configure Oban like the rest of your application:

```elixir
# config/config.exs
config :my_app, Oban,
  repo: MyApp.Repo,
  prune: {:maxlen, 10_000},
  queues: [default: 10, events: 50, media: 20]

# lib/my_app/application.ex
defmodule MyApp.Application do
  @moduledoc false

  use Application

  alias MyApp.Repo
  alias MyAppWeb.Endpoint

  def start(_type, _args) do
    children = [
      Repo,
      Endpoint,
      {Oban, oban_config()}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)
  end

  defp oban_config do
    opts = Application.get_env(:my_app, Oban)

    # Prevent running queues or scheduling jobs from an iex console.
    if Code.ensure_loaded?(IEx) and IEx.started?() do
      opts
      |> Keyword.put(:crontab, false)
      |> Keyword.put(:queues, false)
    else
      opts
    end
  end
end
```

If you are running tests (which you should be) you'll want to disable pruning
, enqueuing scheduled jobs and job dispatching altogether when testing:

```elixir
# config/test.exs
config :my_app, Oban, crontab: false, queues: false, prune: :disabled
```

### Configuring Queues

Queues are specified as a keyword list where the key is the name of the queue
and the value is the maximum number of concurrent jobs. The following
configuration would start four queues with concurrency ranging from 5 to 50:

```elixir
queues: [default: 10, mailers: 20, events: 50, media: 5]
```

There isn't a limit to the number of queues or how many jobs may execute
concurrently in each queue. Here are a few caveats and guidelines:

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

### Defining Workers

Worker modules do the work of processing a job. At a minimum they must define a
`perform/2` function, which is called with an `args` map and the job struct.

Note that the `args` map passed to `perform/2` will _always_ have string keys,
regardless of the key type when the job was enqueued. The `args` are stored as
`jsonb` in PostgreSQL and the serialization process automatically stringifies
all keys.

Define a worker to process jobs in the `events` queue:

```elixir
defmodule MyApp.Business do
  use Oban.Worker, queue: :events

  @impl Oban.Worker
  def perform(%{"id" => id} = args, _job) do
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
  def perform(_args, _job) do
    # do business slowly

    :ok
  end
end
```

The value returned from `perform/2` is ignored, unless it an `{:error, reason}`
tuple. With an error return or when perform has an uncaught exception or throw
then the error is reported and the job is retried (provided there are attempts
remaining).

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

### Pruning Historic Jobs

Job stats and queue introspection are built on keeping job rows in the database
after they have completed. This allows administrators to review completed jobs
and build informative aggregates, at the expense of storage and an unbounded
table size. To prevent the `oban_jobs` table from growing indefinitely, Oban
provides active pruning of `completed` and `discarded` jobs.

By default, pruning retains a conservatively low 1,000 jobs. Pruning is
configured with the `:prune` option. There are three distinct modes of pruning:

* `:disabled` - No pruning happens at all, primarily useful for testing.

* `{:maxlen, count}` - Pruning is based on the number of rows in the table, any
  rows beyond the configured `count` may be deleted. This is the default mode.

* `{:maxage, seconds}` - Pruning is based on a row's age, any rows older than
  the configured number of `seconds` are deleted. The age unit is always
  specified in seconds, but values on the scale of days, weeks or months are
  perfectly acceptable.

#### Caveats & Guidelines

* Pruning is best-effort and performed out-of-band. This means that all limits
  are soft; jobs beyond a specified length or age may not be pruned immediately
  after jobs complete. Prune timing is based on the configured `prune_interval`,
  which is one minute by default.

* If you're using a row-limited database service, like Heroku's hobby plan with
  10M rows, and you have pruning `:disabled`, you could hit that row limit
  quickly by filling up the `oban_beats` table. Instead of fully disabling
  pruning, consider setting a far-out limit: `{:maxage, 60 * 60 * 24 * 365}` (1
  year). You will get the benefit of retaining completed and discarded jobs for
  a year without an unwieldy beats table.

* Pruning is only applied to jobs that are `completed` or `discarded` (has
  reached the maximum number of retries or has been manually killed). It'll
  never delete a new job, a scheduled job or a job that failed and will be
  retried.

### Unique Jobs

The unique jobs feature lets you specify constraints to prevent enqueuing
duplicate jobs.  Uniquness is based on a combination of `args`, `queue`,
`worker`, `state` and insertion time. It is configured at the worker or job
level using the following options:

* `:period` — The number of seconds until a job is no longer considered
  duplicate. You should always specify a period.

* `:fields` — The fields to compare when evaluating uniqueness. The available
  fields are `:args`, `:queue` and `:worker`, by default all three are used.

* `:states` — The job states that are checked for duplicates. The available
  states are `:available`, `:scheduled`, `:executing`, `:retryable` and
  `:completed`. By default all states are checked, which prevents _any_
  duplicates, even if the previous job has been completed.

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

#### Strong Guarantees

Unique jobs are guaranteed through transactional locks and database queries:
they _do not_ rely on unique constraints in the database. This makes uniquness
entirely configurable by application code, without the need for database
migrations.

#### Performance Note

If your application makes heavy use of unique jobs you may want to add an index
on the `args` column of the `oban_jobs` table. The other columns considered for
uniqueness are already covered by indexes.

### Periodic Jobs

Oban allows jobs to be registered with a cron-like schedule and enqueued
automatically. Periodic jobs are registered as a list of `{cron, worker}` or
`{cron, worker, options}` tuples:

```elixir
config :my_app, Oban, repo: MyApp.Repo, crontab: [
  {"* * * * *", MyApp.MinuteWorker},
  {"0 * * * *", MyApp.HourlyWorker, args: %{custom: "arg"}},
  {"0 0 * * *", MyApp.DailyWorker, max_attempts: 1},
  {"0 12 * * MON", MyApp.MondayWorker, queue: :scheduled, tags: ["mondays"]}
]
```

These jobs would be executed as follows:

* `MyApp.MinuteWorker` — Executed once every minute
* `MyApp.HourlyWorker` — Executed at the first minute of every hour with custom args
* `MyApp.DailyWorker` — Executed at midnight every day with no retries
* `MyApp.MondayWorker` — Executed at noon every Monday in the "scheduled" queue

The crontab format respects all [standard rules][cron] and has one minute
resolution. Jobs are considered unique for most of each minute, which prevents
duplicate jobs with multiple nodes and across node restarts.

#### Cron Expressions

Standard Cron expressions are composed of rules specifying the minutes, hours,
days, months and weekdays. Rules for each field are comprised of literal values,
wildcards, step values or ranges:

* `*` — Wildcard, matches any value (0, 1, 2, ...)
* `0` — Literal, matches only itself (only 0)
* `*/15` — Step, matches any value that is a multiple (0, 15, 30, 45)
* `0-5` — Range, matches any value within the range (0, 1, 2, 3, 4, 5)

Each part may have multiple rules, where rules are separated by a comma. The
allowed values for each field are as follows:

* `minute` — 0-59
* `hour` — 0-23
* `days` — 1-31
* `month` — 1-12 (or aliases, `JAN`, `FEB`, `MAR`, etc.)
* `weekdays` — 0-6 (or aliases, `SUN`, `MON`, `TUE`, etc.)

Some specific examples that demonstrate the full range of expressions:

* `0 * * * *` — The first minute of every hour
* `*/15 9-17 * * *` — Every fifteen minutes during standard business hours
* `0 0 * DEC *` — Once a day at midnight during december
* `0 7-9,4-6 13 * FRI` — Once an hour during both rush hours on Friday the 13th

For more in depth information see the man documentation for `cron` and `crontab`
in your system.  Alternatively you can experiment with various expressions
online at [Crontab Guru][guru].

#### Caveats & Guidelines

* All schedules are evaluated as UTC unless a different timezone is configured.
  See `Oban.start_link/1` for information about configuring a timezone.

* Workers can be used for regular and scheduled jobs so long as they accept
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

  config :my_app, Oban, repo: MyApp.Repo, crontab: [
    {"* * * * *", MyApp.SlowWorker, args: custom_args, unique: unique_opts},
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

## Testing

Oban provides some helpers to facilitate testing. The helpers handle the
boilerplate of making assertions on which jobs are enqueued. To use the
`assert_enqueued/1` and `refute_enqueued/1` helpers in your tests you must
include them in your testing module and specify your app's Ecto repo:

```elixir
use Oban.Testing, repo: MyApp.Repo
```

Now you can assert, refute or list jobs that have been enqueued within your
tests:

```elixir
assert_enqueued worker: MyWorker, args: %{id: 1}

# or

refute_enqueued queue: :special, args: %{id: 2}

# or

assert [%{args: %{"id" => 1}}] = all_enqueued worker: MyWorker
```

See the `Oban.Testing` module for more details.

#### Caveats & Guidelines

As noted in [Usage](#Usage), there are some guidelines for running tests:

* Disable all job dispatching by setting `queues: false` or `queues: nil` in
  your `test.exs` config. Keyword configuration is deep merged, so setting
  `queues: []` won't have any effect.

* Disable pruning via `prune: :disabled`. Pruning isn't necessary in testing
  mode because jobs created within the sandbox are rolled back at the end of the
  test. Additionally, the periodic pruning queries will raise
  `DBConnection.OwnershipError` when the application boots.

* Disable cron jobs via `crontab: false`. Periodic jobs aren't useful while
  testing and scheduling can lead to random ownership issues.

* Be sure to use the Ecto Sandbox for testing. Oban makes use of database pubsub
  events to dispatch jobs, but pubsub events never fire within a transaction.
  Since sandbox tests run within a transaction no events will fire and jobs
  won't be dispatched.

  ```elixir
  config :my_app, MyApp.Repo, pool: Ecto.Adapters.SQL.Sandbox
  ```

### Integration Testing

During integration testing it may be necessary to run jobs because they do work
essential for the test to complete, i.e. sending an email, processing media,
etc. You can execute all available jobs in a particular queue by calling
`Oban.drain_queue/1` directly from your tests.

For example, to process all pending jobs in the "mailer" queue while testing
some business logic:

```elixir
defmodule MyApp.BusinessTest do
  use MyApp.DataCase, async: true

  alias MyApp.{Business, Worker}

  test "we stay in the business of doing business" do
    :ok = Business.schedule_a_meeting(%{email: "monty@brewster.com"})

    assert %{success: 1, failure: 0} == Oban.drain_queue(:mailer)

    # Now, make an assertion about the email delivery
  end
end
```

See `Oban.drain_queue/1` for additional details.

## Error Handling

When a job returns an error value, raises an error or exits during execution the
details are recorded within the `errors` array on the job. When the number of
execution attempts is below the configured `max_attempts` limit, the job will
automatically be retried in the future.

The retry delay has an exponential backoff, meaning the job's second attempt
will be after 16s, third after 31s, fourth after 1m 36s, etc.

See the `Oban.Worker` documentation on "Customizing Backoff" for alternative
backoff strategies.

### Error Details

Execution errors are stored as a formatted exception along with metadata about
when the failure ocurred and which attempt caused it. Each error is stored with
the following keys:

* `at` The utc timestamp when the error occurred at
* `attempt` The attempt number when the error ocurred
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
  def perform(_args, _job) do
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

  def handle_event([:oban, :started], measure, meta, _) do
    Logger.warn("[Oban] :started #{meta.worker} at #{measure.start_time}")
  end

  def handle_event([:oban, event], measure, meta, _) when do
    Logger.warn("[Oban] #{event} #{meta.worker} ran in #{measure.duration}")
  end
end
```

Attach the handler to success and failure events in `application.ex`:

```elixir
events = [[:oban, :started], [:oban, :success], [:oban, :failure]]

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
integrating with [Honeybadger][honeybadger] to report job failures:

```elixir
defmodule ErrorReporter do
  def handle_event([:oban, :failure], measure, meta, _) do
    context =
      meta
      |> Map.take([:id, :args, :queue, :worker])
      |> Map.merge(measure)

    Honeybadger.notify(meta.error, context, meta.stack)
  end

  def handle_event([:oban, :trip_circuit], _measure, meta, _) do
    context = Map.take(meta, [:name])

    Honeybadger.notify(meta.error, context, meta.stack)
  end
end

:telemetry.attach_many(
  "oban-errors",
  [[:oban, :failure], [:oban, :trip_circuit]],
  &ErrorReporter.handle_event/4,
  nil
)
```

[tele]: https://hexdocs.pm/telemetry
[honeybadger]: https://honeybadger.io

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
    Supervisor.child_spec({Oban, name: ObanA, repo: Repo}, id: ObanA),
    Supervisor.child_spec({Oban, name: ObanB, repo: Repo, prefix: "special"}, id: ObanB),
    Supervisor.child_spec({Oban, name: ObanC, repo: Repo, prefix: "private"}, id: ObanC)
  ]

  Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)
end
```

## Pulse Tracking

Historic introspection is a defining feature of Oban. In addition to retaining
completed jobs Oban also generates "heartbeat" records every second for each
running queue.

Heartbeat records are recorded in the `oban_beats` table and pruned to five
minutes of backlog. The recorded information is used for a couple of purposes:

1. To track active jobs. When a job executes it records the node and queue that
   ran it in the `attempted_by` column. Zombie jobs (jobs that were left
   executing when a producer crashes or the node is shut down) are found by
   comparing the `attempted_by` values with recent heartbeat records and
   resurrected accordingly.
2. Each heartbeat records information about a node/queue pair such as whether it
   is paused, what the execution limit is and exactly which jobs are running.
   These records can power additional logging or metrics (and are the backbone
   of the Oban UI).

## Troubleshooting

### Querying the Jobs Table

`Oban.Job` defines an Ecto schema and the jobs table can therefore be queried as usual, e.g.:

```
MyApp.Repo.all(
  from j in Oban.Job,
    where: j.worker == "MyApp.Business",
    where: j.state == "discarded"
)
```

### Heroku

#### Elixir and Erlang versions

If your app crashes on launch, be sure to confirm you are running the correct
version of Elixir and Erlang ([view requirements](#Requirements)). If using the
*hashnuke/elixir* buildpack, you can update the `elixir_buildpack.config` file
in your application's root directory to something like:

```
# Elixir version
elixir_version=1.9.0

# Erlang version
erlang_version=22.0.3
```

Available Erlang versions are available [here](https://github.com/HashNuke/heroku-buildpack-elixir-otp-builds/blob/master/otp-versions).

#### Database connections

Make sure that you have enough available database connections when running on
Heroku. Oban uses a database connection in order to listen for pubsub
notifications. This is in addition to your Ecto Repo `pool_size` setting.

Heroku's [Hobby tier Postgres plans](https://devcenter.heroku.com/articles/heroku-postgres-plans#hobby-tier)
have a maximum of 20 connections, so if you're using one of those plan
accordingly.

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

To ensure a commit passes CI you should run `mix ci` locally, which executes the
following commands:

* Check formatting (`mix format --check-formatted`)
* Lint with Credo (`mix credo --strict`)
* Run all tests (`mix test --raise`)
* Run Dialyzer (`mix dialyzer --halt-exit-status`)
