# Handling Expected Failures

Reporting job errors by sending notifications to an external service is
essential to maintaining application health. While reporting is essential, noisy
reports for flaky jobs can become a distraction that gets ignored. Sometimes we
_expect_ that a job will error a few times. That could be because the job relies
on an external service that is flaky, because it is prone to race conditions, or
because the world is a crazy place. Regardless of _why_ a job fails, reporting
every failure may be undesirable.

## Use Case: Silencing Initial Notifications for Flaky Services

One solution for reducing noisy error notifications is to start reporting only
after a job has failed several times. Oban uses [Telemetry][tele] to make
reporting errors and exceptions a simple matter of attaching a handler function.
In this example we will extend [Honeybadger][hb] reporting from the
`Oban.Telemetry` documentation, but account for the number of processing attempts.

To start, we'll define a `Reportable` [protocol][pro] with a single
`reportable?/2` function:

```elixir
defprotocol MyApp.Reportable do
  @fallback_to_any true
  def reportable?(worker, attempt)
end

defimpl MyApp.Reportable, for: Any do
  def reportable?(_worker, _attempt), do: true
end
```

The `Reportable` protocol has a default implementation which always returns
`true`, meaning it reports all errors. Our application has a `FlakyWorker`
that's known to fail a few times before succeeding. We don't want to see a
report until after a job has failed three times, so we'll add an implementation
of `Reportable` within the worker module:

```elixir
defmodule MyApp.Workers.FlakyWorker do
  use Oban.Worker

  defimpl MyApp.Reportable do
    @threshold 3

    def reportable?(_worker, attempt), do: attempt > @threshold
  end

  @impl true
  def perform(%{args: %{"email" => email}}) do
    MyApp.ExternalService.deliver(email)
  end
end
```

The final step is to call `reportable?/2` from our application's error reporter,
passing in the worker module and the attempt number:

```elixir
defmodule MyApp.ErrorReporter do
  alias MyApp.Reportable

  def handle_event(_, _, meta, _) do
    if Reportable.reportable?(meta.job.worker, meta.job.attempt) do
      context = Map.take(meta.job, [:id, :args, :queue, :worker])

      Honeybadger.notify(meta.reason, context, meta.stacktrace)
    end
  end
end
```

Attach the failure handler somewhere in your `application.ex` module:

```elixir
:telemetry.attach("oban-errors", [:oban, :job, :exception], &ErrorReporter.handle_event/4, nil)
```

With the failure handler attached you will start getting error reports **only
after the third error**.

### Giving Time to Recover

If a service is especially flaky you may find that Oban's default backoff
strategy is too fast. By defining a custom `backoff` function on the
`FlakyWorker` we can set a linear delay before retries:

```elixir
# inside of MyApp.Workers.FlakyWorker

@impl true
def backoff(attempt, base_amount \\ 60) do
  attempt * base_amount
end
```

Now the first retry is scheduled `60s` later, the second `120s` later, and so on.

### Building Blocks

Elixir's powerful primitives of behaviours, protocols and event handling make
flexible error reporting seamless and extensible. While our `Reportable`
protocol only considered the number of attempts, this same mechanism is suitable
for filtering by any other `meta` value.

[tele]: https://github.com/beam-telemetry/telemetry
[hb]: https://www.honeybadger.io/
[pro]: https://hexdocs.pm/elixir/Protocol.html
