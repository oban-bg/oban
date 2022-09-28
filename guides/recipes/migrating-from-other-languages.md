# Migrating from Other Languages

Migrating background jobs to Elixir is easy with Oban because everything lives in your PostgreSQL
database. Oban relies on a structured `oban_jobs` table as its job queue, and purposefully uses
JSON as a portable data structures for serialization. That makes enqueueing jobs into Oban simple for
any language with a PostgreSQL adapter—no Oban client necessary.

## Use Case: Inserting Jobs from Rails

It's no secret that Ruby to Elixir is a common migration path for developers and existing
applications alike. Let's explore how to write an adapter for inserting Oban jobs from a Rails
application.

To start, define a skeletal `ActiveRecord` model with a few conveniences for scheduling jobs:

```ruby
class Oban::Job < ApplicationRecord
  # This column is in use, but not used for the insert workflow.
  self.ignored_columns = %w[errors]

  # A simple wrapper around `create` that ensures the job is scheduled immediately.
  def self.insert(worker:, args: {}, queue: "default", scheduled_at: nil)
    create(
      worker: worker,
      queue: queue,
      args: args,
      scheduled_at: scheduled_at || Time.now.utc,
      state: scheduled_at ? "scheduled" : "available"
    )
  end
end
```

The `insert` class method is a convenience that uses named arguments to force passing a `worker`
while providing some defaults. The only semi-magical thing within `insert` is determining the
correct state for scheduled jobs. In Oban, jobs that are ready to execute have an `available`
state, while jobs slated for the future are `scheduled`.

To insert a single job using the `insert` class method:

```ruby
Oban::Job.insert(worker: "MyWorker", args: {id: 1}, queue: "default")
```

Provided your Elixir application has a worker named `MyWorker` and the `default` queue is running,
Oban will pick up and execute the job immediately. To schedule the job to run a minute in the
future instead, pass a `scheduled_at` timestamp:

```ruby
Oban::Job.insert(worker: "MyWorker", args: {id: 1}, scheduled_at: 1.minute.from_now.utc)
```

Now, if you're using Rails 6+, you can also use `insert_all` to batch insert jobs:

```ruby
Oban::Job.insert_all([
  {worker: "MyWorker", args: {id: 1}, queue: "default"},
  {worker: "MyWorker", args: {id: 2}, queue: "default"},
  {worker: "MyWorker", args: {id: 3}, queue: "default"},
])
```

## Safety Guaranteed

Most columns in `oban_jobs` have sensible defaults, so only the `worker` and `args` are typically
required. For integrity, all required columns are marked as `NON NULL`, and several have `CHECK`
constraints as well for extra enforcement.

That's all you need to start migrating background jobs from Rails to Elixir (if you're using Oban,
that is). Naturally, the same pattern would work for Python, Node, PHP, or any other language with
a Postgres adapter.
