# Job Uniqueness

The *uniqueness* of a job is a somewhat complex topic, which is why this guide is here to help you
understand it in detail.

The unique jobs feature lets you specify constraints to prevent enqueuing duplicate jobs.
Uniqueness is based on a combination of job attributes based on the following options:

  * `:period` — The number of seconds until a job is no longer considered duplicate. You should
    always specify a period, otherwise Oban will default to 60 seconds. `:infinity` can be used to
    indicate the job be considered a duplicate as long as jobs are retained (see
    `Oban.Plugins.Pruner`).

  * `:fields` — The fields to compare when evaluating uniqueness. The available fields are
    `:args`, `:queue`, `:worker`, and `:meta`. `:fields` defaults to `[:worker, :queue, :args]`.

  * `:keys` — A specific subset of the `:args` or `:meta` to consider when comparing against
    historic jobs. This allows a job with multiple key/value pairs in its arguments to be compared
    using only a subset of them.

  * `:states` — The job states that are checked for duplicates. The available states are
    described in `t:Oban.Job.unique_state/0`. By default, Oban checks all states except for `:discarded` and `:cancelled`, which prevents duplicates even if the previous job has been completed.

  * `:timestamp` — Which job timestamp to check the period against. The available timestamps are
    `:inserted_at` or `:scheduled_at`. Defaults to `:inserted_at` for legacy reasons.

The simplest form of uniqueness will configure uniqueness for as long as a matching job exists in
the database, regardless of state:

```elixir
use Oban.Worker, unique: true
```

Here's a more complex example which uses multiple criteria:

```elixir
use Oban.Worker,
  unique: [
    # Jobs should be unique for 2 minutes...
    period: 120,
    # ...after being scheduled, not inserted
    timestamp: :scheduled_at,
    # Don't consider the whole :args field, but just the :url field within :args
    keys: [:url],
    # Consider a job unique across all states, including :cancelled/:discarded
    states: Oban.Job.states(),
    # Consider a job unique across workers and queues; only compare the :url key within
    # the :args, as per the :keys configuration above
    fields: [:args]
  ]
```

## Detecting Unique Conflicts

When unique settings match an existing job, the return value of `Oban.insert/2` is still `{:ok,
job}`. However, you can detect a unique conflict by checking the job's `:conflict?` field. If
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

> #### Caveat with `insert_all` {: .warning}
>
> Unless you are using Oban Pro's [Smart Engine][pro-smart-engine], Oban only detects conflicts
> for jobs enqueued through [`Oban.insert/2,3`](`Oban.insert/2`). When using the [Basic
> Engine](`Oban.Engines.Basic`), jobs enqueued through `Oban.insert_all/2` *do not* use per-job
> unique configuration.

## Replacing Values

In addition to detecting unique conflicts, passing options to `:replace` can update any job field
when there is a conflict. Any of the following fields can be replaced per *state*:

  * `:args`
  * `:max_attempts`
  * `:meta`
  * `:priority`
  * `:queue`
  * `:scheduled_at`
  * `:tags`
  * `:worker`

For example, to change the `:priority` and increase `:max_attempts` when there is a conflict with
a job in a `:scheduled` state:

```elixir
BusinessWorker.new(
  args,
  max_attempts: 5,
  priority: 0,
  replace: [scheduled: [:max_attempts, :priority]]
)
```

Another example is bumping the scheduled time on conflict. Either `:scheduled_at` or
`:schedule_in` values will work, but the replace option is always `:scheduled_at`.

```elixir
UrgentWorker.new(args, schedule_in: 1, replace: [scheduled: [:scheduled_at]])
```

> #### Jobs in the `:executing` State {: .error}
>
> If you use this feature to replace a field (such as `:args`) in the `:executing` state by doing
> something like
>
> ```elixir
> UniqueWorker.new(new_args, replace: [executing: [:args]])
> ```
>
> then Oban will update `:args`, but the job will continue executing with the original value.

## Strong Guarantees

Oban **guarantees** uniqueness of jobs through transactional locks and database queries.
Uniqueness *does not* rely on unique constraints in the database. This makes uniqueness entirely
configurable by application code, without the need for database migrations.

[pro-smart-engine]: https://oban.pro/docs/pro/Oban.Pro.Engines.Smart.html
