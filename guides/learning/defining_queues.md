# Defining Queues

Queues are the foundation of how Oban organizes and processes jobs. They allow you to:

- Separate different types of work (e.g., emails, report generation, media processing)
- Control the concurrency of job execution
- Prioritize certain jobs over others
- Manage resource consumption across your application

Each queue operates independently with its own set of worker processes and concurrency limits.

## Basic Queue Configuration

Queues are defined as a keyword list where the key is the name of the queue and the value is the
maximum number of concurrent jobs. The following configuration would start four queues with
concurrency ranging from 5 to 50:

```elixir
config :my_app, Oban,
  queues: [default: 10, mailers: 20, events: 50, media: 5],
  repo: MyApp.Repo
```

In this example:

- The `default` queue will process up to 10 jobs simultaneously
- The `mailers` queue will process up to 20 jobs simultaneously
- The `events` queue will process up to 50 jobs simultaneously
- The `media` queue will process up to 5 jobs simultaneously

## Advanced Queue Configuration

For more control, you can use an expanded form to configure queues with individual overrides:

```elixir
config :my_app, Oban,
  queues: [
    default: 10,
    mailers: [limit: 20, dispatch_cooldown: 50],
    events: [limit: 50, paused: true],
    media: [limit: 1, global_limit: 10]
  ],
  repo: MyApp.Repo
```

This expanded configuration demonstrates several advanced options:

* The `mailers`  queue has a dispatch cooldown of 50ms between job fetching
* The `events` queue starts in a paused state, which means it won't process anything until
  `Oban.resume_queue/2` is called to start it
* The `media` queue uses a global limit (an Oban Pro feature)

### Paused Queues

When a queue is configured with `paused: true`, it won't process any jobs until explicitly
started. This is useful for:

* Maintenance periods
* Controlling when resource-intensive jobs can run
* Temporarily disabling certain types of jobs

You can resume a paused queue programmatically:

```elixir
Oban.resume_queue(queue: :events)
```

And pause an active queue:

```elixir
Oban.pause_queue(queue: :media)
```

## Queue Planning Guidelines

There isn't a limit to the number of queues or how many jobs may execute concurrently in each
queue. However, consider these important guidelines:

#### Resource Considerations

* Each queue will run as many jobs as possible concurrently, up to the configured limit. Make sure
  your system has enough resources (such as *database connections*) to handle the concurrent load.

* Consider the total concurrency across all queues. For example, if you have 4 queues with limits
  of 10, 20, 30, and 40, your system needs to handle up to 100 concurrent jobs, each potentially
  requiring database connections and other resources.

#### Concurrency and Distribution

* Queue limits are **local** (per-node), not global (per-cluster). For example, running a queue
  with a local limit of `2` on three separate nodes is effectively a global limit of *six
  concurrent jobs*. If you require a global limit, you must restrict the number of nodes running a
  particular queue or consider Oban Pro's [Smart Engine][smart], which can manage global
  concurrency *automatically*!

#### Queue Planning

* Only jobs in the configured queues will execute. Jobs in any other queue will stay in the
  database untouched. Be sure to configure all queues you intend to use.

* Organize queues by workload characteristics. For example:

  - CPU-intensive jobs might benefit from a dedicated low-concurrency queue
  - I/O-bound jobs (like sending emails) can often use higher concurrency
  - Priority work should have dedicated queues with higher concurrency

#### External Process Considerations

* Pay attention to the number of concurrent jobs making expensive system calls (such as calls to
  resource-intensive tools like [FFMpeg][ffmpeg] or [ImageMagick][imagemagick]). The BEAM ensures
  that the system stays responsive under load, but those guarantees don't apply when using ports
  or shelling out commands.

* Consider creating dedicated queues with lower concurrency for jobs that interact with external
  processes or services that have their own concurrency limitations.

[ffmpeg]: https://www.ffmpeg.org
[imagemagick]: https://imagemagick.org/index.php
[smart]: https://oban.pro/docs/pro/Oban.Pro.Engines.Smart.html
