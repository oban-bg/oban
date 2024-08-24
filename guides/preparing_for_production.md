# Preparing for Production

There are a few additional bits of configuration to consider before you're ready to run Oban in
production. In development and test environments, job data is short lived and there's no scale to
contend with. Now we'll dig into enabling introspection, external observability, and maintaining
database health.

## Logging

Oban heavily utilizes Telemetry for instrumentation at every level. From job execution, plugin
activity, through to every database call there's a telemetry event to hook into.

The simplest way to leverage Oban's telemetry usage is through the default logger, available with
`Oban.Telemetry.attach_default_logger/1`. Attach the logger in your `application.ex`:

```elixir
defmodule MyApp.Application do
  use Application

  @impl Application
  def start(_type, _args) do
    Oban.Telemetry.attach_default_logger()

    children = [
      ...
    ]
  end
end
```

By default, the logger emits JSON encoded logs at the `:info` level. You can disable encoding and
fall back to structured logging with `encode: false`, or change the log level with the `:level`
option.

For example, to log without encoding at the `:debug` level:

```elixir
Oban.Telemetry.attach_default_logger(encode: false, level: :debug)
```

## Pruning Jobs

Job introspection and uniqueness relies on keeping job rows in the database after they have
executed. To prevent the `oban_jobs` table from growing indefinitely, the `Oban.Plugins.Pruner`
plugin provides out-of-band deletion of `completed`, `cancelled` and `discarded` jobs.

Retaining jobs for 7 days is a good starting point, but depending on throughput, you may wish to
keep jobs for even longer. Include `Pruner` in the list of plugins and configure it to retain jobs
for 7 days, specified in seconds:

```elixir
config :my_app, Oban,
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
  ...
```

## Rescuing Jobs

During deployment or unexpected node restarts jobs may be left in an executing state indefinitely.
We call these jobs "orphans", but orphaning isn't a bad thing. It means that the job wasn't lost
and it may be retried again when the system comes back online.

There are two mechanisms to mitigate orphans:

1. Use the `Oban.Plugins.Lifeline` plugin to automatically move those jobs back to available so
   they can run again.
2. Increase the `shutdown_grace_period` to allow the system more time to finish executing before
   shutdown.

Even with a higher `shutdown_grace_period` it's possible to have orphans if there is an unexpected
crash or extra long running jobs.

Consider adding the `Lifeline` plugin and configure it to rescue after a generous period of time,
like 30 minutes:

```elixir
config :my_app, Oban,
  plugins: [
    {Oban.Plugins.Lifeline, rescue_after: :timer.minutes(30)},
  ...
```

## Error Handling

Telemetry events can be used to report issues externally to services like Sentry or AppSignal.
Write a handler that sends error notifications to a third party (use a mock, or something that
sends a message back to the test process).

You can use exception events to send error reports to Honeybadger, Rollbar, AppSignal, ErroTracker 
or any other application monitoring platform.

Some libraries like AppSignal, ErrorTracker or Sentry automatically handle these events without 
requiring any extra code on your application. You can take a look at ErrorTracker's 
[Oban integration](https://github.com/elixir-error-tracker/error-tracker/blob/main/lib/error_tracker/integrations/oban.ex) 
as an example on how to attach to and use `Oban.Telemetry` events.

If you need a custom integration you can add a reporter module that fit your needs. 
Here's an example reporter module for [Sentry](https://hex.pm/packages/sentry):

```elixir
defmodule MyApp.ObanReporter do
  def attach do
    :telemetry.attach("oban-errors", [:oban, :job, :exception], &__MODULE__.handle_event/4, [])
  end

  def handle_event([:oban, :job, :exception], measure, meta, _) do
    extra =
      meta.job
      |> Map.take([:id, :args, :meta, :queue, :worker])
      |> Map.merge(measure)

    Sentry.capture_exception(meta.reason, stacktrace: meta.stacktrace, extra: extra)
  end
end
```

Attach the handler when your application boots:

```elixir
# application.ex
@impl Application
def start(_type, _args) do
  MyApp.ObanReporter.attach()
end
```

## Ship It!

Now you're ready to ship to production with essential logging, error reporting, and baseline
job maintenance.

For additional observability and introspection, consider integrating with one of these external
tools built on `Oban.Telemetry`:

* [Oban Web](https://getoban.pro)—an official Oban package, it's a view of jobs, queues, and
  metrics that you host directly within your application. Powered by Phoenix Live View and Oban
  Metrics, it is extremely lightweight and continuously updated.

* [PromEx](https://hex.pm/packages/prom_ex)—Prometheus metrics and Grafana dashboards based on
  metrics from job events, producer events, and also from internal polling jobs to monitor queue
  sizes.

* [AppSignal](https://docs.appsignal.com/elixir/integrations/oban.html)—The AppSignal for Elixir
  package instruments jobs performed by Oban workers, and collects metrics about your jobs'
  performance.

* [ErrorTracker](https://hex.pm/packages/error_tracker)—An Elixir-based open source error tracking
  solution that automatically integrates with Oban. It allows you to store and view exceptions on
  your app without external services. It's powered by Telemetry, Ecto and Phoenix LiveView.
