# Error Handling

This page guides you through handling errors in Oban.

The basics: jobs can fail in expected or unexpected ways. To mark a job as failed, you can return
`{:error, reason}` from a worker's [`perform/1` callback](`c:Oban.Worker.perform/1`), as
documented in the `t:Oban.Worker.result/0` type. A job can also fail because of unexpected raised
errors or exits.

In any case, when a job fails the details of the failure are recorded in the `errors` array on the
`Oban.Job` struct.

## Error Details

Oban stores execution errors as a list of maps (`t:Oban.Job.errors/0`). Each error contains the
following keys:

  * `:at` — The UTC timestamp when the error occurred at
  * `:attempt` — The attempt number when the error occurred
  * `:error` — A *formatted* error message and stacktrace

See the [Instrumentation docs](instrumentation.html) for an example of integrating with external
error reporting systems.

## Retries

When a job fails and the number of execution attempts is below the configured `max_attempts` limit
for that job, the job will automatically be retried in the future. If the number of failures
reaches `max_attempts`, the job gets **discarded**.

The retry delay has an exponential backoff, meaning the job's second attempt will be after 16s,
third after 31s, fourth after 1m 36s, and so on.

See the `Oban.Worker` documentation on "Customizing Backoff" for alternative backoff strategies.

### Limiting Retries

By default, jobs are retried up to 20 times. The number of retries is controlled by the
`:max_attempts` value, which can be set at the **worker** or **job** level. For example, to
instruct a worker to discard jobs after three failures:

```elixir
use Oban.Worker, queue: :limited, max_attempts: 3
```
