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
- [Oban Pro](#-oban-pro)
- [Engines](#engines)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quick Getting Started](#quick-getting-started)
- [Learning](#learning)
- [Community](#community)
- [Contributing](#contributing)

---

> [!NOTE]
>
> This README is for the unreleased main branch, please reference the [official documentation on
> hexdocs][hexdoc] for the latest stable release.

[hexdoc]: https://hexdocs.pm/oban/Oban.html

---

<!-- MDOC -->

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
  Each queue runs in isolation, with its own concurrency limits, ensuring that a job in a single
  slow queue can't back up other faster queues.

- **Isolated Jobs** — Every job runs in a dedicated process to provide fully concurrent execution,
  a clean environment between jobs, and efficient cleanup after the job runs.

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

## 🌟 Oban Pro

An official set of extensions, plugins, and workers that expand what Oban is capable of is
available as a licensed package. It includes features like:

* 🖇️ [Workflows][wor]
* 🎨 [Decorators][dec]
* ⛓️  [Chains][cha]
* 🏗️ [Structured Jobs][str]
* 🪝 [Worker Hooks][hoo]
* 🌎 [Global Limits][glo]
* 🔪 [Queue Partitioning][par]
* 🎢 [Dynamic Queues][dyn]

Plus [much more][ove]. Learn more about [Oban Pro](https://oban.pro#oban-pro)

[cha]: https://oban.pro/docs/pro/Oban.Pro.Worker.html#module-chained-jobs
[dec]: https://oban.pro/docs/pro/Oban.Pro.Decorator.html
[dyn]: https://oban.pro/docs/pro/Oban.Pro.Plugins.DynamicQueues.html
[glo]: https://oban.pro/docs/pro/Oban.Pro.Engines.Smart.html#module-global-concurrency
[hoo]: https://oban.pro/docs/pro/Oban.Pro.Worker.html#module-worker-hooks
[par]: https://oban.pro/docs/pro/Oban.Pro.Engines.Smart.html#module-queue-partitioning
[ove]: https://oban.pro/docs/pro/overview.html
[str]: https://oban.pro/docs/pro/Oban.Pro.Worker.html#module-structured-jobs
[wor]: https://oban.pro/docs/pro/Oban.Pro.Workers.Workflow.html

## Engines

Oban ships with engines for [PostgreSQL][postgres], [MySQL][mysql], and [SQLite3][sqlite3]. Each
engine supports the same core functionality, though they have differing levels of maturity and
suitability for production.

[postgres]: https://www.postgresql.org/
[mysql]: https://www.mysql.com/
[sqlite3]: https://www.sqlite.org/

## Requirements

Oban requires:

* Elixir 1.15+
* Erlang 24+
* PostgreSQL 12.0+, MySQL 8.4+, or SQLite3 3.37.0+

## Installation

See the [installation guide](https://hexdocs.pm/oban/installation.html) for details on installing
and configuring Oban in your application.

## Quick Getting Started

  1. [Configure queues](https://hexdocs.pm/oban/Oban.html#module-configuring-queues) and an Ecto repo for Oban to
     use:

     ```elixir
     # In config/config.exs
     config :my_app, Oban,
       repo: MyApp.Repo,
       queues: [mailers: 20]
     ```

  2. Define a worker to process jobs in the `mailers` queue (see `Oban.Worker`):

     ```elixir
     defmodule MyApp.MailerWorker do
       use Oban.Worker, queue: :mailers

       @impl Oban.Worker
       def perform(%Oban.Job{args: %{"email" => email} = _args}) do
         _ = Email.deliver(email)
         :ok
       end
     end
     ```

  3. Enqueue a job (see [the documentation](https://hexdocs.pm/oban/Oban.Job.html#enqueueing-jobs)):

     ```elixir
     %{email: %{to: "foo@example.com", body: "Hello from Oban!"}}
     |> MyApp.MailerWorker.new()
     |> Oban.insert()
     ```

  4. The magic happens! Oban executes the job when there is available bandwidth in the
     `mailer` queue.

## Learning

Learn the fundamentals of Oban, all the way through to preparing for production with our LiveBook
powered [Oban Training](https://github.com/oban-bg/oban_training/) curriculum.

<!-- MDOC -->

## Community

There are a few places to connect and communicate with other Oban users:

- Ask questions and discuss *#oban* on the [Elixir Forum][forum]
- [Request an invitation][invite] and join the *#oban* channel on Slack
- Learn about bug reports and upcoming features in the [issue tracker][issues]

[invite]: https://elixir-slack.community/
[forum]: https://elixirforum.com/
[issues]: https://github.com/sorentwo/oban/issues

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
