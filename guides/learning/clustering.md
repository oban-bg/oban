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

## Leadership and Peer Configuration

Oban uses a peer-based leadership system to coordinate work across nodes in a cluster. Leadership
is essential for preventing duplicate work—only the leader node runs global plugins like `Cron`,
`Lifeline`, and `Stager`.

### How Leadership Works

* Each Oban instance checks for leadership at 30-second intervals
* When the current leader exits, it broadcasts a message encouraging other nodes to assume
  leadership
* Only one node per Oban instance name can be the leader at any time
* Without leadership, global plugins won't run on any node

### Available Peer Implementations

Oban provides two peer implementations:

* `Oban.Peers.Database` — Uses the `oban_peers` table for leadership coordination. Works in any
  environment, with or without clustering. This is the default and recommended for production.

* `Oban.Peers.Global` — Uses Erlang's `:global` module for leadership. Requires Distributed
  Erlang, but handles development restarts more gracefully. Recommended for development
  environments where leadership delays can be problematic.

A third, pseudo, mode is to disable leadership entirely with `peer: false` or `plugins: false`.
This is useful when you explicitly don't want a node to become leader (e.g., web-only nodes that
don't run plugins).

### Configuring Peers

```elixir
# Use in development for faster leadership transitions
config :my_app, Oban,
  peer: Oban.Peers.Global,
  ...

# Disable leadership on web-only nodes that don't run plugins
config :my_app, Oban,
  peer: false,
  ...
```

[pg_bouncer]: http://www.pgbouncer.org
