# Recursive Jobs

Recursive jobs, like recursive functions, call themselves after they have
executed. Except unlike recursive functions, where recursion happens in a tight
loop, a recursive job enqueues a new version of itself and may add a slight
delay to alleviate pressure on the queue.

Recursive jobs are a great way to backfill large amounts of data where a
database migration or a mix task may not be suitable. Here are a few reasons
that a recursive job may be better suited for backfilling data:

* Data can't be backfilled with a database migration, it may require talking to
  an external service
* A task may fail partway through execution; resuming the task would mean
  starting over again, or tracking progress manually to resume where the failure
  occurred
* A task may be computationally intensive or put heavy pressure on the database
* A task may run for too long and would be interrupted by code releases or other
  node restarts
* A task may interface with an external service and require some rate limiting
* A job can be used directly for new records _and_ to backfill existing records

Let's explore recursive jobs with a use case that builds on several of those
reasons.

## Use Case: Backfilling Timezone Data

Consider a worker that queries an external service to determine what timezone a
user resides in. The external service has a rate limit and the response time is
unpredictable. We have a lot of users in our database missing timezone
information, and we need to backfill.

Our application has an existing `TimezoneWorker` that accepts a user's `id`,
makes an external request and then updates the user's timezone. We can modify
the worker to handle backfilling by adding a new clause to `perform/1`. The new
clause explicitly checks for a `backfill` argument and will enqueue the next job
after it executes:

```elixir
defmodule MyApp.Workers.TimezoneWorker do
  use Oban.Worker

  import Ecto.Query

  alias MyApp.{Repo, User}

  @backfill_delay 1

  @impl true
  def perform(%{args: %{"id" => id, "backfill" => true}}) do
    with :ok <- perform(%{args: %{"id" => id}}) do
      case fetch_next(id) do
        next_id when is_integer(next_id) ->
          %{id: next_id, backfill: true}
          |> new(schedule_in: @backfill_delay)
          |> Oban.insert()

        nil ->
          :ok
      end
    end
  end

  def perform(%{args: %{"id" => id}}) do
    update_timezone(id)
  end

  defp fetch_next(current_id) do
    User
    |> where([u], is_nil(u.timezone))
    |> where([u], u.id > ^current_id)
    |> order_by(asc: :id)
    |> limit(1)
    |> select([u], u.id)
    |> Repo.one()
  end

  defp update_timezone(_id), do: Enum.random([:ok, {:error, :reason}])
end
```

There is a lot happening in the worker module, so let's unpack it a little bit.

1. There are two clauses for `perform/1`, the first only matches when a job is
   marked as `"backfill" => true`, the second does the actual work of updating the
   timezone.
2. The backfill clause checks that the timezone update succeeds and then uses
   `fetch_next/1` to look for the id of the next user without a timezone.
3. When another user needing a backfill is available it enqueues a new backfill
   job with a one second delay.

With the new `perform/1` clause in place and our code deployed we can kick off
the recursive backfill. Assuming the `id` of the first user is `1`, you can
start the job from an `iex` console:

```elixir
iex> %{id: 1, backfill: true} |> MyApp.Workers.TimezoneWorker.new() |> Oban.insert()
```

Now the jobs will chug along at a steady rate of one per second until the
backfill is complete (or something fails). If there are any errors the backfill
will pause until the failing job completes: especially useful for jobs relying
on flaky external services. Finally, when there aren't any more user's without a
timezone, the backfill is complete and recursion will stop.

## Building On Recursive Jobs

This was a relatively simple example, and hopefully it illustrates the power and
flexibility of recursive jobs. Recursive jobs are a general pattern and aren't
specific to Oban. In fact, aside from the `use Oban.Worker` directive there
isn't anything specific to Oban in the recipe!
