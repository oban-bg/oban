# Oban Usage Rules

## Overview
Oban is a robust, observable background job processing framework for Elixir backed by modern SQL databases (PostgreSQL, SQLite3, and MySQL). It executes jobs concurrently across independently isolated queues, enqueues jobs transactionally with application records using Ecto, and retains job history in the database for auditing and metrics.

## Setup
Add `:oban` to `deps` in `mix.exs`:
```elixir
{:oban, "~> 2.24"}
```

Generate and run the database migration:
```elixir
# lib/my_app/repo/migrations/add_oban_jobs_table.exs
defmodule MyApp.Repo.Migrations.AddObanJobsTable do
  use Ecto.Migration

  def up, do: Oban.Migration.up(version: 14)
  def down, do: Oban.Migration.down(version: 1)
end
```

Configure Oban in `config/config.exs` and `config/test.exs`:
```elixir
# config/config.exs
config :my_app, Oban,
  engine: Oban.Engines.Basic, # Oban.Engines.Lite for SQLite, Oban.Engines.Dolphin for MySQL
  repo: MyApp.Repo,
  queues: [default: 10, mailers: 20],
  pruner: [max_age: {1, :day}],
  lifeline: [rescue_after: {2, :hours}]

# config/test.exs
config :my_app, Oban, testing: :manual
```

Add Oban to your application supervision tree:
```elixir
# lib/my_app/application.ex
children = [
  MyApp.Repo,
  {Oban, Application.fetch_env!(:my_app, Oban)}
]
```

## Core Usage Patterns
- **Define workers with `use Oban.Worker`**: Set compile-time defaults for queue, priority, max attempts, and tags:
  ```elixir
  defmodule MyApp.MailWorker do
    use Oban.Worker, queue: :mailers, max_attempts: 10, priority: 1

    @impl Oban.Worker
    def perform(%Oban.Job{args: %{"email" => email}}) do
      MyApp.Mailer.deliver(email)
      :ok
    end
  end
  ```
- **Return explicit status tuples from `perform/1`**: Return `:ok` or `{:ok, val}` on success, `{:error, reason}` to retry with backoff, `{:cancel, reason}` to halt permanently without retries, or `{:snooze, period}` to postpone without consuming an attempt:
  ```elixir
  def perform(%Oban.Job{args: %{"id" => id}}) do
    case MyApp.ExternalApi.fetch(id) do
      {:ok, result} -> :ok
      {:rate_limited, wait} -> {:snooze, {wait, :seconds}}
      {:permanent_failure, err} -> {:cancel, err}
      {:error, err} -> {:error, err}
    end
  end
  ```
- **Enqueue jobs via `Oban.insert/2`**: Build changesets via `MyWorker.new/2` and insert into the database:
  ```elixir
  %{user_id: 123} |> MyApp.MailWorker.new(priority: 0) |> Oban.insert()
  ```
- **Enqueue transactionally with `Ecto.Multi`**: Use `Oban.insert/3,4` to guarantee jobs commit atomically alongside business data:
  ```elixir
  Ecto.Multi.new()
  |> Ecto.Multi.insert(:user, user_changeset)
  |> Oban.insert(:job, fn %{user: user} -> MyApp.MailWorker.new(%{id: user.id}) end)
  |> MyApp.Repo.transaction()
  ```
- **Bulk insert with `Oban.insert_all/1,2`**: Pass a list or stream of changesets (returns a list of inserted `Job` structs):
  ```elixir
  users |> Enum.map(&MyApp.MailWorker.new(%{id: &1.id})) |> Oban.insert_all()
  ```
- **Schedule jobs with `scheduled_in` or `scheduled_at`**: Use relative `{amount, unit}` tuples or absolute UTC `DateTime` structs:
  ```elixir
  MyApp.MailWorker.new(args, scheduled_in: {5, :minutes})
  MyApp.MailWorker.new(args, scheduled_at: ~U[2026-10-04 12:00:00Z])
  ```
- **Deduplicate jobs with `unique` options**: Prevent duplicate enqueues by configuring period, fields, keys, and states:
  ```elixir
  use Oban.Worker, unique: [period: {1, :hour}, keys: [:user_id], states: :successful]
  ```
- **Update attributes on unique conflicts**: Use `:replace` to bump schedules or fields when an enqueue conflicts:
  ```elixir
  MyApp.MailWorker.new(args, scheduled_in: 60, replace: [scheduled: [:scheduled_at]])
  ```
- **Manage queues and jobs dynamically at runtime**:
  ```elixir
  Oban.pause_queue(queue: :mailers)
  Oban.resume_queue(queue: :mailers)
  Oban.scale_queue(queue: :mailers, limit: 30)
  Oban.cancel_job(job_or_id)
  Oban.retry_job(job_or_id)
  ```

## Configuration
- `engine`: Engine module. Defaults to `Oban.Engines.Basic` (Postgres); use `Oban.Engines.Lite` for SQLite3, `Oban.Engines.Dolphin` for MySQL.
- `repo`: Repo module `MyApp.Repo` or `{MyApp.Repo, log: false, dynamic_repo: fn -> ... end}`.
- `queues`: Keyword list of `[queue_name: limit]` or `[queue_name: [limit: 10, paused: true, dispatch_cooldown: 50]]`. Set `queues: false` or `queues: []` on worker-less nodes.
- `cron`: Crontab schedules via `Oban.Cron`: `cron: [crontab: [{"0 2 * * *", MyApp.NightlyWorker}, {"@hourly", MyApp.HourlyWorker, args: %{...}}]]`.
- `pruner`: Background pruning via `Oban.Pruner`: `pruner: [max_age: {1, :day}]`. Always configure in production to prevent table bloat.
- `lifeline`: Rescues orphaned jobs stuck in `executing` after unexpected shutdowns: `lifeline: [rescue_after: {1, :hour}]`.
- `reindexer`: Periodically rebuilds indexes concurrently to eliminate bloat: `reindexer: Oban.Reindexer` or `reindexer: [schedule: "@weekly"]`.
- `stager`: Moves `scheduled` and `retryable` jobs to `available`: `stager: [interval: {1, :second}]`.
- `shutdown_grace_period`: Milliseconds to allow active jobs to finish before stopping queues (default: `15_000`).

## Common Mistakes to Avoid
- **Matching on atom keys in `perform/1`**: Job `args` are stored as JSON in the database and always decoded with string keys. Always pattern match on string keys (`%{"user_id" => id}`), never atom keys.
- **Passing non-JSON-encodable terms in args**: Args must be JSON maps. Do not pass atoms, tuples, PIDs, or un-encoded structs as args.
- **Using `insert_all` for unique jobs with Basic engine**: Open-source Oban does not enforce uniqueness during bulk `insert_all`. Enqueue unique jobs individually with `Oban.insert/2`.
- **Returning deprecated `:discard` tuples**: `:discard` and `{:discard, reason}` are deprecated; return `{:cancel, reason}` to halt a job.
- **Using `Application.get_env/2` inside `use Oban.Worker`**: Worker options are evaluated at compile time. Pass dynamic runtime options to `Worker.new/2`.
- **Omitting insertion states from unique `:states`**: Custom `:states` lists must include an insert state (`:available`, `:scheduled`, or `:suspended`); otherwise, duplicates can be inserted before earlier jobs change state.
- **Assuming queue concurrency is cluster-wide**: Concurrency limits are local to each node. A queue limit of 10 across 3 nodes executes up to 30 jobs concurrently.
- **Using legacy `Oban.Plugins.*` namespace**: In v2.24+, configure built-in services using dedicated top-level keys (`cron`, `lifeline`, `pruner`, `reindexer`, `stager`) instead of `:plugins`.
- **Assuming `replace: [executing: [:args]]` updates running code**: Updating `:args` on an executing job updates the database record only; the active process continues with the original args.
- **Passing non-UTC DateTime to `scheduled_at`**: Oban requires UTC timestamps. Shift any local datetimes to UTC (`DateTime.shift_zone!(dt, "Etc/UTC")`) before scheduling.

## Testing
- Configure `:manual` mode in `config/test.exs` (`config :my_app, Oban, testing: :manual`) to disable background polling and avoid Ecto sandbox issues.
- Import test helpers via `use Oban.Testing, repo: MyApp.Repo` in `test/support/data_case.ex` or individual test files.
- **Unit test workers with `perform_job/2,3`**: Executes `perform/1` in-process with stringified args and validates the return type without touching queues:
  ```elixir
  assert :ok = perform_job(MyApp.MailWorker, %{email: "test@example.com"})
  assert {:error, "failed"} = perform_job(MyApp.MailWorker, %{"email" => "invalid"})
  ```
- **Assert or refute enqueued jobs**:
  ```elixir
  assert_enqueued worker: MyApp.MailWorker, args: %{email: "test@example.com"}
  refute_enqueued worker: MyApp.MailWorker, queue: :special
  assert [%{args: %{"email" => _}}] = all_enqueued(worker: MyApp.MailWorker)
  ```
- **Assert relative scheduling in tests**: Use `scheduled_in` to verify future jobs without manual timestamp math:
  ```elixir
  assert_enqueued worker: MyApp.MailWorker, scheduled_in: {1, :hour}
  ```
- **Execute enqueued jobs synchronously with `drain_queue/1,2`**:
  ```elixir
  assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :mailers)
  Oban.drain_queue(queue: :mailers, with_scheduled: true, with_recursion: true)
  ```
- **Temporarily change test modes**: Use `Oban.Testing.with_testing_mode/2` to run specific tests in `:inline` or `:manual` mode:
  ```elixir
  Oban.Testing.with_testing_mode(:inline, fn ->
    assert {:ok, %Oban.Job{state: "completed"}} = Oban.insert(MyApp.MailWorker.new(%{}))
  end)
  ```
