# Troubleshooting

## PG Bouncer

### No Notifications with Transaction Pooling

Using PG Bouncer's "Transaction Pooling" setup disables all of PostgreSQL's
`LISTEN` and `NOTIFY` activity. Some functionality, such as triggering job
execution, scaling queues, canceling jobs, etc. rely on those notifications.

To ensure full functionality you must use a Repo that connects directly to the
database, or use another mode like "Session Pooling" if possible.

If you **must** use "Transaction Pooling" you can use the [Repeater][repe]
plugin to ensure that queues keep processing jobs:

```elixir
config :my_app, Oban,
  plugins: [Oban.Plugins.Pruner, Oban.Plugins.Stager, Oban.Plugins.Repeater],
  ...
```

_Note: The Repeater plugin keeps jobs processing, it will not faciliate other
notification based functionality, e.g. scaling queues._

[repe]: Oban.Plugins.Repeater.html

## Heroku

### Elixir and Erlang Versions

If your app crashes on launch, be sure to confirm you are running the correct
version of Elixir and Erlang ([view requirements](#Requirements)). If using the
*hashnuke/elixir* buildpack, you can update the `elixir_buildpack.config` file
in your application's root directory to something like:

```
# Elixir version
elixir_version=1.9.0

# Erlang version
erlang_version=22.0.3
```

Available Erlang versions are available [here][versions].

[versions]: https://github.com/HashNuke/heroku-buildpack-elixir-otp-builds/blob/master/otp-versions.

### Database Connections

Make sure that you have enough available database connections when running on
Heroku. Oban uses a database connection in order to listen for pubsub
notifications. This is in addition to your Ecto Repo `pool_size` setting.

Heroku's [Hobby tier Postgres plans][plans] have a maximum of 20 connections, so
if you're using one of those plan accordingly.

[plans]: https://devcenter.heroku.com/articles/heroku-postgres-plans#hobby-tier
