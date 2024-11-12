# Configuration

This page details generic configuration options.

## Configuring Queues

You can define queues as a keyword list where the key is the name of the queue and the value is
the maximum number of concurrent jobs. The following configuration would start four queues with
concurrency ranging from 5 to 50:

```elixir
config :my_app, Oban,
  queues: [default: 10, mailers: 20, events: 50, media: 5],
  repo: MyApp.Repo
```

You may also use an expanded form to configure queues with individual overrides:

```elixir
queues: [
  default: 10,
  events: [limit: 50, paused: true]
]
```

The `events` queue will now start in a paused state, which means it won't process anything until
`Oban.resume_queue/2` is called to start it.

There isn't a limit to the number of queues or how many jobs may execute
concurrently in each queue. Some additional guidelines:

  * Each queue will run as many jobs as possible concurrently, up to the configured limit. Make
  sure your system has enough resources (such as *database connections*) to handle the concurrent
  load.

  * Queue limits are **local** (per-node), not global (per-cluster). For example, running a queue
  with a local limit of `2` on three separate nodes is effectively a global limit of *six
  concurrent jobs*. If you require a global limit, you must restrict the number of nodes running a
  particular queue or consider Oban Pro's [Smart Engine][smart], which can manage global
  concurrency *automatically*!
  * Only jobs in the configured queues will execute. Jobs in any other queue will
  stay in the database untouched.

  * Pay attention to the number of concurrent jobs making expensive system calls (such as calls to
  resource-intensive tools like [FFMpeg][ffmpeg] or [ImageMagick][imagemagick]). The BEAM ensures
  that the system stays responsive under load, but those guarantees don't apply when using ports
  or shelling out commands.

[ffmpeg]: https://www.ffmpeg.org
[imagemagick]: https://imagemagick.org/index.php
