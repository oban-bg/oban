# Reliable Scheduled Jobs

A common variant of recursive jobs are "scheduled jobs", where the goal is for a
job to repeat indefinitely with a fixed amount of time between executions. The
part that makes it "reliable" is the guarantee that we'll keep retrying the
job's business logic when the job retries, but we'll **only schedule the next
occurrence once**. In order to achieve this guarantee we'll make use of the
`perform` function to receive a complete `Oban.Job` struct.

Time for illustrative example!

## Use Case: Delivering Daily Digest Emails

When a new user signs up to use our site we need to start sending them daily
digest emails. We want to deliver the emails around the same time a user signed
up, repeating every 24 hours. It is important that we don't spam them with
duplicate emails, so we ensure that the next email is only scheduled on our
first attempt.

```elixir
defmodule MyApp.Workers.ScheduledWorker do
  use Oban.Worker, queue: :scheduled, max_attempts: 10

  alias MyApp.Mailer

  @one_day 60 * 60 * 24

  @impl true
  def perform(%{args: %{"email" => email} = args, attempt: 1}) do
    args
    |> new(schedule_in: @one_day)
    |> Oban.insert!()

    Mailer.deliver_email(email)
  end

  def perform(%{args: %{"email" => email}}) do
    Mailer.deliver_email(email)
  end
end
```

You'll notice that the first `perform/1` clause only matches a job struct on the
first attempt. When it matches, the first clause schedules the next iteration
immediately, _before_ attempting to deliver the email. Any subsequent retries
fall through to the second `perform/1` clause, which only attempts to deliver
the email again. Combined, the clauses get us close to **at-most-once semantics
for scheduling**, and **at-least-once semantics for delivery**.

## More Flexible Than CRON Scheduling

Delivering around the same time using cron-style scheduling would need extra
book-keeping to check when a user signed up, and then only deliver to those
users that signed up within that window of time. The recursive scheduling
approach is more accurate and entirely self contained—when and if the digest
interval changes the scheduling will pick it up automatically once our code
deploys.

_An [extensive discussion][oi27] on the Oban issue tracker prompted this example
along with the underlying feature that made it possible._

[oi27]: https://github.com/sorentwo/oban/issues/27
