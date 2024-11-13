# Clustering

Oban supports running in clusters of nodes. It supports both nodes that are connected to each
other (via *distributed Erlang*), as well as nodes that are not connected to each other but that
communicate via the database's pubsub mechanism.

Usually, scheduled job management operates in **global mode** and notifies queues of available
jobs via pub/sub to minimize database load. However, when pubsub isn't available, staging
switches to a **local mode** where each queue polls independently.

Local mode is less efficient and will only happen if you're running in an environment where
neither PostgreSQL nor PG notifications work. That situation should be rare and limited to the
following conditions:

  1. Running with a connection pooler, like [pg_bouncer], in transaction mode.
  2. Running without clustering, that is, without *distributed Erlang*.

If **both** of those criteria apply and pubsub notifications won't work, then staging will switch
to polling in local mode.

[pg_bouncer]: http://www.pgbouncer.org
