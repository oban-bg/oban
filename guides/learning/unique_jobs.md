# Unique Jobs

The *uniqueness* of a job is a somewhat complex topic. This guide is here to help you understand its complexities!

The unique jobs feature allows you to specify constraints to prevent *enqueuing* duplicate jobs.
These constraints only apply when jobs are inserted. Uniqueness has no bearing on whether jobs
are *executed* concurrently.
Uniqueness is based on a combination of job attributes based on the following options:

  * `:period` — The number of seconds until a job is no longer considered duplicate. You should
    always specify a period, otherwise Oban will default to 60 seconds. `:infinity` can be used to
    indicate the job be considered a duplicate as long as jobs are retained (see
    `Oban.Plugins.Pruner`).

  * `:fields` — The fields to compare when evaluating uniqueness. The available fields are
    `:args`, `:queue`, `:worker`, and `:meta`. `:fields` defaults to `[:worker, :queue, :args]`.
    It's recommended that you leave the default `:fields`, otherwise you risk unexpected conflicts
    between unrelated jobs.

  * `:keys` — A specific subset of the `:args` or `:meta` to consider when comparing against
    historic jobs. This allows a job with multiple key/value pairs in its arguments to be compared
    using only a subset of them.

  * `:states` — The job states that are checked for duplicates. You can use a named group or
    a list of individual states. The available named groups are:

    * `:all` - All states
    * `:incomplete` - Jobs that haven't completed processing
    * `:scheduled` - Only `scheduled` jobs (useful for "debouncing")
    * `:successful` - Jobs that aren't `cancelled` or `discarded` (the default)

    By default, `:successful` is used, which prevents duplicates even if the previous job has been completed.

  * `:timestamp` — Which job timestamp to check the period against. The available timestamps are
    `:inserted_at` or `:scheduled_at`. Defaults to `:inserted_at` for legacy reasons.

The simplest form of uniqueness will configure uniqueness for as long as a matching job exists in
the database, regardless of state:

```elixir
use Oban.Worker, unique: true
```

Here's a more complex example which uses multiple options:

```elixir
use Oban.Worker,
  unique: [
    # Jobs should be unique for 2 minutes...
    period: {2, :minutes},
    # ...after being scheduled, not inserted
    timestamp: :scheduled_at,
    # Don't consider the whole :args field, but just the :url field within :args
    keys: [:url],
    # Consider a job unique across all states, including :cancelled/:discarded
    states: :all,
    # Consider a job unique across queues; only compare the :url key within
    # the :args, as per the :keys configuration above
    fields: [:worker, :args]
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

## Unique Guarantees

Oban **strives** for uniqueness of jobs through transactional locks and database queries.
Uniqueness *does not* rely on unique constraints in the database, which leaves it prone to race
conditions in some circumstances. However, Pro's Smart Engine does rely on unique constraints and
provides strong uniqueness guarantees.

[pro-smart-engine]: https://oban.pro/docs/pro/Oban.Pro.Engines.Smart.html

## Specifying Fields and Keys

The `:fields` option determines which high-level job attributes Oban will consider when
checking for uniqueness, including `:args`, `:queue`, `:worker`, and `:meta`.

When `:args` or `:meta` are included in the `:fields` list, the `:keys` option provides additional
specificity by allowing you to designate particular keys within the map for comparison, rather
than comparing the entire args map.

Let's see this with an example:

```elixir
# This compares the entire args map
use Oban.Worker,
  unique: [fields: [:worker, :queue, :args]]

# This compares only the :url key within the args map
use Oban.Worker,
  unique: [keys: [:url], fields: [:worker, :queue, :args]]
```

In the second example, the uniqueness check only looks at the `:url` key within the `:args` map
because `:keys` is specified.
