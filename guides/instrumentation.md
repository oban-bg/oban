# Instrumentation, Error Reporting, and Logging

Oban provides integration with [Telemetry][telemetry], a dispatching library for
metrics and instrumentation. It is easy to report Oban metrics to any backend by attaching to Telemetry events prefixed with `:oban`.

Here is an example of an unstructured log handler:

```elixir
defmodule MyApp.ObanLogger do
  require Logger

  def handle_event([:oban, :job, :start], measure, meta, _) do
    Logger.warning("[Oban] :started #{meta.worker} at #{measure.system_time}")
  end

  def handle_event([:oban, :job, event], measure, meta, _) do
    Logger.warning("[Oban] #{event} #{meta.worker} ran in #{measure.duration}")
  end
end
```

Attach the handler to success and failure events in your application's `c:Application.start/2` callback (usually in `lib/my_app/application.ex`):

```elixir
def start(_type, _args) do
  events = [
    [:oban, :job, :start],
    [:oban, :job, :stop],
    [:oban, :job, :exception]
  ]

  :telemetry.attach_many("oban-logger", events, &MyApp.ObanLogger.handle_event/4, [])

  Supervisor.start_link(...)
end
```

The `Oban.Telemetry` module provides a robust structured logger that handles all
of Oban's telemetry events. As in the example above, attach it within your
application module:

```elixir
:ok = Oban.Telemetry.attach_default_logger()
```

For more details on the default structured logger and information on event
metadata see docs for the `Oban.Telemetry` module.

## Reporting Errors

Another great use of execution data and instrumentation is error reporting. Here is an example of an event handler module that
integrates with [Honeybadger][honeybadger] to report job failures:

```elixir
defmodule MyApp.ErrorReporter do
  def attach do
    :telemetry.attach(
      "oban-errors",
      [:oban, :job, :exception],
      &__MODULE__.handle_event/4,
      []
    )
  end

  def handle_event([:oban, :job, :exception], measure, meta, _) do
    Honeybadger.notify(meta.reason, stacktrace: meta.stacktrace)
  end
end

# Attach it with:
MyApp.ErrorReporter.attach()
```

You can use exception events to send error reports to Sentry, AppSignal, Honeybadger, Rollbar, or any other application monitoring platform.

### Built-in Reporting

Some error-reporting and application-monitoring services support reporting Oban errors out of the box:

  - Sentry — [Oban integration documentation][sentry-integration]
  - AppSignal — [Oban integration documentation][appsignal-integration]

[honeybadger]: https://www.honeybadger.io
[telemetry]: https://github.com/beam-telemetry/telemetry
[sentry-integration]: https://docs.sentry.io/platforms/elixir/integrations/oban
[appsignal-integration]: https://docs.appsignal.com/elixir/integrations/oban.html
