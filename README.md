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
  <a href="https://circleci.com/gh/sorentwo/oban">
    <img alt="CircleCI Status" src="https://circleci.com/gh/sorentwo/oban.svg?style=svg">
  </a>
  <a href="https://opensource.org/licenses/MIT">
    <img alt="MIT License" src="https://img.shields.io/badge/License-MIT-blue.svg">
  </a>
</p>

## Table of Contents

- [Features](#Features)
- [Requirements](#Requirements)
- [Installation](#Installation)
- [Usage](#Usage)
  - [Configuring Queues](#Configuring-Queues)
  - [Creating Workers](#Creating-Workers)
  - [Enqueuing Jobs](#Enqueueing-Jobs)
- [Testing](#Testing)
- [Contributing](#Contributing)

## Features

Oban's primary goals are **reliability**, **consistency** and **observability**.
It is fundamentally different from other background job processing tools because
it retains job data for historic metrics and inspection. You can leave your
application running indefinitely without worrying about jobs being lost or
orphaned due to crashes.

Advantages over in-memory, mnesia, Redis and RabbitMQ based tools:

- **Fewer Dependencies** — If you are running a web app there is a _very good_
  chance that you're running on top of a [RDBMS][rdbms]. Running your job queue
  within PostgreSQL minimizes system dependencies and simplifies data backups.
- **Transactional Control** — Enqueue a job along with other database changes,
  ensuring that everything is committed or rolled back atomically.
- **Database Backups** — Jobs are stored inside of your primary database, which
  means they are backed up together with the data that they relate to.

Advanced features and advantages over other RDBMS based tools:

- **Isolated Queues** — Jobs are stored in a single table but are executed in
  distinct queues. Each queue runs in isolation, ensuring that a jobs in a single
  slow queue can't back up other faster queues.
- **Queue Control** — Queues can be paused, resumed and scaled independently at
  runtime.
- **Job Killing** — Jobs can be killed in the middle of execution regardless of
  which node they are running on. This stops the job at once and flags it as
  `discarded`.
- **Triggered execution** — Database triggers ensure that jobs are dispatched as
  soon as they are inserted into the database.
- **Scheduled Jobs** — Jobs can be scheduled at any time in the future, down to
  the second.
- **Job Safety** — When a process crashes or the BEAM is terminated executing
  jobs aren't lost—they are quickly recovered by other running nodes or
  immediately when the node is restarted.
- **Historic Metrics** — After a job is processed the row is _not_ deleted.
  Instead, the job is retained in the database to provide metrics. This allows
  users to inspect historic jobs and to see aggregate data at the job, queue or
  argument level.
- **Node Metrics** — Every queue broadcasts metrics during runtime. These are
  used to monitor queue health across nodes.
- **Queue Draining** — Queue shutdown is delayed so that slow jobs can finish
  executing before shutdown.
- **Telemetry Integration** — Job life-cycle events are emitted via
  [Telemetry][tele] integration. This enables simple logging, error reporting
  and health checkups without plug-ins.

[rdbms]: https://en.wikipedia.org/wiki/Relational_database#RDBMS
[tele]: https://github.com/beam-telemetry/telemetry

## Requirements

Oban has been developed and actively tested with Elixir 1.8+, Erlang/OTP 21.1+
and PostgreSQL 11.0+. Running Oban currently requires Elixir 1.8+ and PostgreSQL
9.6+.

## Installation

Oban is published on [Hex](https://hex.pm/packages/oban). Add it to your list of
dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:oban, "~> 0.2"}
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

Open the generated migration in your editor and delegate the `up` and `down`
functions to `Oban.Migrations`:

```elixir
defmodule MyApp.Repo.Migrations.AddObanJobsTable do
  use Ecto.Migration

  defdelegate up, to: Oban.Migrations
  defdelegate down, to: Oban.Migrations
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

## Usage

Oban isn't an application and won't be started automatically. It is started by a
supervisor that must be included in your application's supervision tree. All of
your configuration is passed into the `Oban` supervisor, allowing you to
configure Oban like the rest of your application.

```elixir
# confg/config.exs
config :my_app, Oban,
  repo: MyApp.Repo,
  prune: {:maxlen, 100_000},
  queues: [default: 10, events: 50, media: 20]

# lib/my_app/application.ex
defmodule MyApp.Application do
  @moduledoc false

  use Application

  alias MyApp.{Endpoint, Repo}

  def start(_type, _args) do
    children = [
      Repo,
      Endpoint,
      {Oban, Application.get_env(:my_app, Oban)}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)
  end
end
```

If you are running tests (which you should be) you'll need to disable pruning
and job dispatching altogether when testing:

```elixir
# config/test.exs
config :my_app, Oban,
  queues: false,
  prune: :disabled
```

Without dispatch and pruning disabled Ecto will raise constant ownership errors
and you won't be able to run tests.

#### Configuring Queues

Queues are specified as a keyword list where the key is the name of the queue
and the value is the maximum number of concurrent jobs. The following
configuration would start four queues with concurrency ranging from 5 to 50:

```elixir
queues: [default: 10, mailers: 20, events: 50, media: 5]
```

There isn't a limit to the number of queues or how many jobs may execute
concurrently. Here are a few caveats and guidelines:

* Each queue will run as many jobs as possible concurrently, up to the
  configured limit. Make sure your system has enough resources (i.e. database
  connections) to handle the concurrent load.
* Only jobs in the configured queues will execute. Jobs in any other queue
  will stay in the database untouched.
* Be careful how many concurrent jobs make expensive system calls (i.e. FFMpeg,
  ImageMagick). The BEAM ensures that the system stays responsive under load,
  but those guarantees don't apply when using ports or shelling out commands.

#### Creating Workers

Worker modules do the work of processing a job. At a minimum they must define a
`perform/1` function, which is called with an `args` map.

Define a worker to process jobs in the `events` queue:

```elixir
defmodule MyApp.Workers.Business do
  use Oban.Worker, queue: "events", max_attempts: 10

  @impl Oban.Worker
  def perform(%{"id" => id}) do
    model = MyApp.Repo.get(MyApp.Business.Man, id)

    IO.inspect(model)
  end
end
```

The return value of `perform/1` doesn't matter and is entirely ignored. If the
job raises an exception or throws an exit then the error will be reported and
the job will be retried (provided there are attempts remaining).

#### Enqueueing Jobs

Jobs are simply Ecto strucs and are enqueued by inserting them into the
database. Here we insert a job into the `default` queue and specify the worker
by module name:

```elixir
%{id: 1, user_id: 2}
|> Oban.Job.new(queue: :default, worker: MyApp.Worker)
|> MyApp.Repo.insert()
```

For convenience and consistency all workers implement a `new/2` function that
converts an args map into a job changeset suitable for inserting into the
database:

```elixir
%{in_the: "business", of_doing: "business"}
|> MyApp.Workers.Business.new()
|> MyApp.Repo.insert()
```

The worker's defaults may be overridden by passing options:

```elixir
%{vote_for: "none of the above"}
|> MyApp.Workers.Business.new(queue: "special", max_attempts: 5)
|> MyApp.Repo.insert()
```

Jobs may be scheduled or delayed down to the second any time in the future:

```elixir
%{id: 1}
|> MyApp.Workers.Business.new(scheduled_in: 5)
|> MyApp.Repo.insert()
```

## Testing

As noted in the Usage section above there are some guidelines for running tests:

* Disable all job dispatching by setting `queues: false` or `queues: nil` in your `test.exs`
  config. Keyword configuration is deep merged, so setting `queues: []` won't have any effect.

* Disable pruning via `prune: :disabled`. Pruning isn't necessary in testing mode because jobs
  created within the sandbox are rolled back at the end of the test. Additionally, the periodic
  pruning queries will raise `DBConnection.OwnershipError` when the application boots.

* Be sure to use the Ecto Sandbox for testing. Oban makes use of database pubsub
  events to dispatch jobs, but pubsub events never fire within a transaction.
  Since sandbox tests run within a transaction no events will fire and jobs
  won't be dispatched.

  ```elixir
  config :my_app, MyApp.Repo, pool: Ecto.Adapters.SQL.Sandbox
  ```

Oban provides some helpers to facilitate testing. The helpers handle the
boilerplate of making assertions on which jobs are enqueued. To use the
`assert_enqueued/1` and `refute_enqueued/1` helpers in your tests you must
include them in your testing module and specify your app's Ecto repo:

```elixir
use Oban.Testing, repo: MyApp.Repo
```

Now you can assert or refute that jobs have been enqueued within your tests:

```elixir
assert_enqueued worker: MyWorker, args: %{id: 1}

# or

refute_enqueued queue: "special", args: %{id: 2}
```

See the `Oban.Testing` module for more details.

## Integration Testing

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

## Contributing

To run the Oban test suite you must have PostgreSQL 10+ running locally with a
database named `oban_test`. Follow these steps to create the database, create
the database and run all migrations:

```bash
# Create the database
MIX_ENV=test mix ecto.create -r Oban.Test.Repo

# Run the base migration
MIX_ENV=test mix ecto.migrate -r Oban.Test.Repo
```

To ensure a commit passes CI you should run `mix ci` locally, which executes the
following commands:

* Check formatting (`mix format --check-formatted`)
* Lint with Credo (`mix credo --strict`)
* Run all tests (`mix test`)
* Run Dialyzer (`mix dialyzer --halt-exit-status`)
