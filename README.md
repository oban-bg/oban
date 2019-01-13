Kiq is the most powerful software I have ever built. It is also the most
complex—which I believe to be unnecessary.

Oban is a refinement and simplification of Kiq/Sidekiq. Much of the complexity
inside of Kiq is an artifact of integrating with Sidekiq and adhering to its
hodgepodge use of Redis data types. With the release of Redis 5 we now have streams,
which are powerful enough to model queues, retries, scheduled jobs, backup jobs and
job resurrection _in a single data type_.

Here are my gripes, complaints and general thoughts about the shortcomings of
Kiq and Sidekiq:

* Many of the pro/enterprise features that Kiq provides are implemented in a
  very brittle way. This was done for interoperability with the Sidekiq UI and
  isn't necessary in a green field system.
* The client and pooling system are deeply intertwined with Redis, which makes
  testing very opaque and running jobs in-line impossible.
* There is a heavy reliance on polling for pushing jobs, fetching jobs and
  performing retries. With blocking stream operations we have a more responsive
  system with greater accuracy.
* The reporter system introduces a layer of asynchrony that could cause jobs not
  to be retried, logged or have statistics recorded. The reporter system will be
  replaced with middleware that can run _synchronously_ before or after a job.
* The lack of key namespacing makes it impossible to run integration tests
  asynchronously.
* As Kiq's feature set grew so did the reliance on Lua scripts to orchestrate
  atomic operations such as dequeueing, descheduling and taking locks. With
  streams we don't need to rely on scripting for any of our operations. Not that
  there is anything wrong with Lua or using scripts, but it adds to the overall
  complexity.
* There is integration with the Telemetry library, but it isn't leveraged. It
  can be used by library users to build a logger, we don't need to provide that.
* Workers in Kiq are static and executed in isolation. Only job arguments are
  passed to `perform/1`, which makes it impossible for the function to know
  anything else about the job being executed. Job execution should be a step in
  a pipeline where a `call` function is passed a job structure and must return a
  job structure.

Miscellaneous thoughts and notes:

* The XINFO command provides detail about the size of a stream and also the
  number of pending jobs.
* Stats should be namespaced and contained in a single HASH.
* Process information is set to expire every minute, there isn't any point in
  recording it. Instead, use pubsub to broadcast information about running jobs.
* GenStage and Redix have been rock solid. Keep with that.
* Avoiding global state and `Application` configuration is perfect. Keep doing
  that.
* Try to make more/better use of property based tests. Can I use Proper instead
  of StreamData to get stateful properties defined?
* The underlying structure and behavior should be easily replicated in other
  languages (ruby, python, node).
* Get rid of the `init` function and optional callback.
