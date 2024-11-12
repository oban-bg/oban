<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/oban-bg/oban/main/assets/oban-logotype-dark.png">
    <source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/oban-bg/oban/main/assets/oban-logotype-light.png">
    <img alt="Oban logo" src="https://raw.githubusercontent.com/oban-bg/oban/main/assets/oban-logotype-light.png" width="320">
  </picture>
</p>

<p align="center">
  Robust job processing in Elixir, backed by modern PostgreSQL, MySQL, and SQLite3.
  Reliable, <br /> observable, and loaded with <a href="#features">enterprise grade features</a>.
</p>

<p align="center">
  <a href="https://hex.pm/packages/oban">
    <img alt="Hex Version" src="https://img.shields.io/hexpm/v/oban.svg">
  </a>

  <a href="https://hexdocs.pm/oban">
    <img alt="Hex Docs" src="http://img.shields.io/badge/hex.pm-docs-green.svg?style=flat">
  </a>

  <a href="https://github.com/oban-bg/oban/actions">
    <img alt="CI Status" src="https://github.com/oban-bg/oban/workflows/ci/badge.svg">
  </a>

  <a href="https://opensource.org/licenses/Apache-2.0">
    <img alt="Apache 2 License" src="https://img.shields.io/hexpm/l/oban">
  </a>
</p>

## Table of Contents

- [Features](#features)
- [Oban Web+Pro](#oban-webpro)
- Usage
  - [Engines](#engines)
  - [Requirements](#requirements)
  - [Learning](#learning)
  - [Installation](#installation)
  - [Configuring Queues](#configuring-queues)
  - [Defining Workers](#defining-workers)
  - [Enqueueing Jobs](#enqueueing-jobs)
  - [Scheduling Jobs](#scheduling-jobs)
  - [Prioritizing Jobs](#prioritizing-jobs)
  - [Unique Jobs](#unique-jobs)
  - [Pruning Historic Jobs](#pruning-historic-jobs)
  - [Periodic Jobs](https://hexdocs.pm/oban/periodic_jobs.html)
  - [Error Handling](https://hexdocs.pm/oban/error_handling.html)
  - [Instrumentation and Logging](https://hexdocs.pm/oban/instrumentation.html)
  - [Instance and Database Isolation](https://hexdocs.pm/oban/isolation.html)
- [Community](#community)
- [Contributing](#contributing)

---

> [!NOTE]
>
> This README is for the unreleased main branch, please reference the [official documentation on
> hexdocs][hexdoc] for the latest stable release.

[hexdoc]: https://hexdocs.pm/oban/Oban.html

---

## Features

Oban's primary goals are **reliability**, **consistency** and **observability**.

Oban is a powerful and flexible library that can handle a wide range of background job use cases,
and it is well-suited for systems of any size. It provides a simple and consistent API for
scheduling and performing jobs, and it is built to be fault-tolerant and easy to monitor.

Oban is fundamentally different from other background job processing tools because _it retains job
data for historic metrics and inspection_. You can leave your application running indefinitely
without worrying about jobs being lost or orphaned due to crashes.

#### Advantages Over Other Tools

- **Fewer Dependencies** — If you are running a web app there is a _very good_ chance that you're
  running on top of a SQL database. Running your job queue within a SQL database minimizes system
  dependencies and simplifies data backups.

- **Transactional Control** — Enqueue a job along with other database changes, ensuring that
  everything is committed or rolled back atomically.

- **Database Backups** — Jobs are stored inside of your primary database, which means they are
  backed up together with the data that they relate to.

#### Advanced Features

- **Isolated Queues** — Jobs are stored in a single table but are executed in distinct queues.
  Each queue runs in isolation, ensuring that a job in a single slow queue can't back up other
  faster queues.

- **Queue Control** — Queues can be started, stopped, paused, resumed and scaled independently at
  runtime locally or across _all_ running nodes (even in environments like Heroku, without
  distributed Erlang).

- **Resilient Queues** — Failing queries won't crash the entire supervision tree, instead a
  backoff mechanism will safely retry them again in the future.

- **Job Canceling** — Jobs can be canceled in the middle of execution regardless of which node
  they are running on. This stops the job at once and flags it as `cancelled`.

- **Triggered Execution** — Insert triggers ensure that jobs are dispatched on all connected nodes
  as soon as they are inserted into the database.

- **Unique Jobs** — Duplicate work can be avoided through unique job controls. Uniqueness can be
  enforced at the argument, queue, worker and even sub-argument level for any period of time.

- **Scheduled Jobs** — Jobs can be scheduled at any time in the future, down to the second.

- **Periodic (CRON) Jobs** — Automatically enqueue jobs on a cron-like schedule. Duplicate jobs
  are never enqueued, no matter how many nodes you're running.

- **Job Priority** — Prioritize jobs within a queue to run ahead of others with ten levels of
  granularity.

- **Historic Metrics** — After a job is processed the row isn't deleted. Instead, the job is
  retained in the database to provide metrics. This allows users to inspect historic jobs and to
  see aggregate data at the job, queue or argument level.

- **Node Metrics** — Every queue records metrics to the database during runtime. These are used to
  monitor queue health across nodes and may be used for analytics.

- **Graceful Shutdown** — Queue shutdown is delayed so that slow jobs can finish executing before
  shutdown. When shutdown starts queues are paused and stop executing new jobs. Any jobs left
  running after the shutdown grace period may be rescued later.

- **Telemetry Integration** — Job life-cycle events are emitted via [Telemetry][tele] integration.
  This enables simple logging, error reporting and health checkups without plug-ins.

[tele]: https://github.com/beam-telemetry/telemetry

## Oban Web+Pro

> [!TIP]
> A web dashboard for managing Oban, along with an official set of extensions, plugins, and
> workers that expand what Oban is capable are available as licensed packages:
> 
> * [🧭 Oban Web](https://oban.pro#oban-web)
> * [🌟 Oban Pro](https://oban.pro#oban-pro)
> 
> Learn more at [oban.pro][pro]!

<!-- MDOC -->

## Engines

Oban ships with engines for [PostgreSQL][postgres], [MySQL][mysql], and [SQLite3][sqlite3]. Each
engine supports the same core functionality, though they have differing levels of maturity and
suitability for production.

[postgres]: https://www.postgresql.org/
[mysql]: https://www.mysql.com/
[sqlite3]: https://www.sqlite.org/

## Requirements

Oban requires: 

* Elixir 1.14+
* Erlang 24+
* PostgreSQL 12.0+, MySQL 8.0+, or SQLite3 3.37.0+

## Learning

Learn the fundamentals of Oban, all the way through to preparing for production with our LiveBook
powered [Oban Training](https://github.com/oban-bg/oban_training/) curriculum. 

## Installation

See the [installation guide](https://hexdocs.pm/oban/installation.html) for details on installing
and configuring Oban in your application.

## Configuring Queues

Queues are specified as a keyword list where the key is the name of the queue
and the value is the maximum number of concurrent jobs. The following
configuration would start four queues with concurrency ranging from 5 to 50:

```elixir
config :my_app, Oban,
  queues: [default: 10, mailers: 20, events: 50, media: 5],
  repo: MyApp.Repo
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

## Defining Workers

Worker modules do the work of processing a job. At a minimum they must define a
`perform/1` function, which is called with an `%Oban.Job{}` struct.

Note that the `args` field of the job struct will _always_ have string keys, regardless of the key
type when the job was enqueued. The `args` are stored as JSON and the serialization process
automatically stringifies all keys. Also, because `args` are always encoded as JSON, you must
ensure that all values are serializable, otherwise you'll have encoding errors when inserting jobs.

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

The `use` macro also accepts options to customize `max_attempts`, `priority`, `tags`, `unique`,
and `replace` options:

```elixir
defmodule MyApp.LazyBusiness do
  use Oban.Worker,
    queue: :events,
    priority: 3,
    max_attempts: 3,
    tags: ["business"],
    unique: true,
    replace: [scheduled: [:scheduled_at]]

  @impl Oban.Worker
  def perform(_job) do
    # do business slowly

    :ok
  end
end
```

Like all `use` macros, options are defined at compile time. Avoid using `Application.get_env/2` to
define worker options. Instead, pass dynamic options at runtime by passing them to
`MyWorker.new/2`:

```elixir
MyApp.MyWorker.new(args, queue: dynamic_queue)
```

Successful jobs should return `:ok` or an `{:ok, value}` tuple. The value returned from
`perform/1` is used to control whether the job is treated as a success, a failure, cancelled or
deferred for retrying later.

See the `Oban.Worker` docs for more details on failure conditions and `Oban.Telemetry` for details
on job reporting.

## Enqueueing Jobs

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

Unique jobs can be configured in the worker, or when the job is built:

```elixir
%{email: "brewster@example.com"}
|> MyApp.Mailer.new(unique: false)
|> Oban.insert()
```

Job priority can be specified using an integer from 0 to 9, with 0 being the
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

## Scheduling Jobs

Jobs may be scheduled down to the second any time in the future:

```elixir
%{id: 1}
|> MyApp.Business.new(schedule_in: 5)
|> Oban.insert()
```

Jobs may also be scheduled at a specific datetime in the future:

```elixir
%{id: 1}
|> MyApp.Business.new(scheduled_at: ~U[2020-12-25 19:00:56.0Z])
|> Oban.insert()
```

Scheduling is _always_ in UTC. You'll have to shift timestamps in other zones to
UTC before scheduling:

```elixir
%{id: 1}
|> MyApp.Business.new(scheduled_at: DateTime.shift_zone!(datetime, "Etc/UTC"))
|> Oban.insert()
```

#### Caveats & Guidelines

Usually, scheduled job management operates in `global` mode and notifies queues
of available jobs via PubSub to minimize database load. However, when PubSub
isn't available, staging switches to a `local` mode where each queue polls
independently.

Local mode is less efficient and will only happen if you're running in an
environment where neither `Postgres` nor `PG` notifications work. That situation
should be rare and limited to the following conditions:

1. Running with a connection pooler, i.e., `pg_bouncer`, in transaction mode.
2. Running without clustering, i.e., without Distributed Erlang

If **both** of those criteria apply and PubSub notifications won't work, then
staging will switch to polling in `local` mode.

## Prioritizing Jobs

Normally, all available jobs within a queue are executed in the order they were scheduled. You can
override the normal behavior and prioritize or de-prioritize a job by assigning a numerical
`priority`.

* Priorities from 0-9 are allowed, where 0 is the highest priority and 9 is the lowest.

* The default priority is 0, unless specified all jobs have an equally high priority.

* All jobs with a higher priority will execute before any jobs with a lower priority. Within a
  particular priority jobs are executed in their scheduled order.

#### Caveats & Guidelines

The default priority is defined in the jobs table. The least intrusive way to change it for all
jobs is to change the column default:

```elixir
alter table("oban_jobs") do
  modify :priority, :integer, default: 1, from: {:integer, default: 0}
end
```

## Unique Jobs

The unique jobs feature lets you specify constraints to prevent enqueueing duplicate jobs.
Uniqueness is based on a combination of job attribute based on the following options:

* `:period` — The number of seconds until a job is no longer considered duplicate. You should
  always specify a period, otherwise Oban will default to 60 seconds. `:infinity` can be used to
  indicate the job be considered a duplicate as long as jobs are retained.

* `:fields` — The fields to compare when evaluating uniqueness. The available fields are `:args`,
  `:queue`, `:worker`, and `:meta`. By default, fields is set to `[:worker, :queue, :args]`.

* `:keys` — A specific subset of the `:args` or `:meta` to consider when comparing against
  historic jobs. This allows a job with multiple key/value pairs in the args to be compared using
  only a subset of them.

* `:states` — The job states that are checked for duplicates. The available states are
  `:available`, `:scheduled`, `:executing`, `:retryable`, `:completed`, `:cancelled` and
  `:discarded`. By default all states except for `:discarded` and `:cancelled` are checked, which
  prevents duplicates even if the previous job has been completed.

* `:timestamp` — Which timestamp to check the period against. The available timestamps are
  `:inserted_at` or `:scheduled_at`, and it defaults to `:inserted_at` for legacy reasons.

The simplest form of uniqueness will configure uniqueness for as long as a matching job exists in
the database, regardless of state:

```elixir
use Oban.Worker, unique: true
```

Configure the worker to be unique only for 60 seconds:

```elixir
use Oban.Worker, unique: [period: 60]
```

Check the `:scheduled_at` timestamp instead of `:inserted_at` for uniqueness:

```elixir
use Oban.Worker, unique: [period: 120, timestamp: :scheduled_at]
```

Only consider the `:url` key rather than the entire `args`:

```elixir
use Oban.Worker, unique: [keys: [:url]]
```

Use `Oban.Job.states/0` to specify uniqueness across _all_ states, including `cancelled` and
`discarded`:

```elixir
use Oban.Worker, unique: [period: :infinity, states: Oban.Job.states()]
```

#### Detecting Unique Conflicts

When unique settings match an existing job, the return value of `Oban.insert/2` is still `{:ok,
job}`. However, you can detect a unique conflict by checking the jobs' `:conflict?` field. If
there was an existing job, the field is `true`; otherwise it is `false`.

You can use the `:conflict?` field to customize responses after insert:

```elixir
case Oban.insert(changeset) do
  {:ok, %Job{id: nil, conflict?: true}} ->
    {:error, :failed_to_acquire_lock}

  {:ok, %Job{conflict?: true}} ->
    {:error, :job_already_exists}

  result ->
    result
end
```

Note that, unless you are using Oban Pro's Smart Engine, conflicts are only detected for jobs
enqueued through `Oban.insert/2,3`. When using the Basic Engine, jobs enqueued through
`Oban.insert_all/2` _do not_ use per-job unique configuration.

#### Replacing Values

In addition to detecting unique conflicts, passing options to `replace` can update any job field
when there is a conflict. Any of the following fields can be replaced per _state_:  `args`,
`max_attempts`, `meta`, `priority`, `queue`, `scheduled_at`, `tags`, `worker`.

For example, to change the `priority` and increase `max_attempts` when there is a conflict with a
job in a `scheduled` state:

```elixir
BusinessWorker.new(
  args,
  max_attempts: 5,
  priority: 0,
  replace: [scheduled: [:max_attempts, :priority]]
)
```

Another example is bumping the scheduled time on conflict. Either `scheduled_at` or `schedule_in`
values will work, but the replace option is always `scheduled_at`.

```elixir
UrgentWorker.new(args, schedule_in: 1, replace: [scheduled: [:scheduled_at]])
```

NOTE: If you use this feature to replace a field (e.g. `args`) in the
`executing` state by doing something like: `UniqueWorker.new(new_args, replace:
[executing: [:args]])` Oban will update the `args`, but the job will continue
executing with the original value.

#### Strong Guarantees

Unique jobs are guaranteed through transactional locks and database queries:
they _do not_ rely on unique constraints in the database. This makes uniqueness
entirely configurable by application code, without the need for database
migrations.

## Testing

Find testing setup, helpers, and strategies in the [testing guide](https://hexdocs.pm/oban/testing.html).

[pro]: https://oban.pro

## Pruning Historic Jobs

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

<!-- MDOC -->

## Community

There are a few places to connect and communicate with other Oban users:

- Ask questions and discuss *#oban* on the [Elixir Forum][forum]
- [Request an invitation][invite] and join the *#oban* channel on [Slack][slack]
- Learn about bug reports and upcoming features in the [issue tracker][issues]
- Follow [@sorentwo][twitter] (Twitter)

[invite]: https://elixir-slack.community/
[slack]: https://elixir-lang.slack.com/
[forum]: https://elixirforum.com/
[issues]: https://github.com/sorentwo/oban/issues
[twitter]: https://twitter.com/sorentwo

## Contributing

To run the Oban test suite you must have PostgreSQL 12+ and MySQL 8+ running. Follow these steps
to create the database, create the database and run all migrations:

```bash
mix test.setup
```

To ensure a commit passes CI you should run `mix test.ci` locally, which executes the following
commands:

* Check formatting (`mix format --check-formatted`)
* Check deps (`mix deps.unlock --check-unused`)
* Lint with Credo (`mix credo --strict`)
* Run all tests (`mix test --raise`)
* Run Dialyzer (`mix dialyzer`)
