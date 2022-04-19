# Changelog for Oban v2.12

_🌟 Looking for changes to Web or Pro? Check the [Oban.Pro Changelog][opc] or
the [Oban.Web Changelog][owc]. 🌟_

[Oban v2.12 Upgrade Guide](v2-12.html)

Oban v2.12 was dedicated to enriching the testing experience and expanding
config, plugin, and queue validation across all environments.

## Testing Modes

Testing modes bring a new, vastly improved, way to configure Oban for testing.
The new `testing` option makes it explicit that Oban should operate in a
restricted mode for the given environment.

Behind the scenes, the new testing modes rely on layers of validation within
Oban's `Config` module. Now production configuration is validated automatically
during test runs. Even though queues and plugins aren't _started_ in the test
environment, their configuration is still validated.

To switch, stop overriding `plugins` and `queues` and enable a testing mode
in your `test.exs` config:

```elixir
config :my_app, Oban, testing: :manual
```

Testing in `:manual` mode is identical to testing in older versions of Oban:
jobs won't run automatically so you can use helpers like `assert_enqueued` and
execute them manually with `Oban.drain_queue/2`.

An alternate `:inline` allows Oban to bypass all database interaction and run
jobs _immediately in the process that enqueued them_.

```elixir
config :my_app, Oban, testing: :inline
```

Finally, new [testing guides][tst] cover test setup, unit [testing
workers][tsw], integration [testing queues][tsq], and testing [dynamic
configuration][tsc].

[tst]: testing.html
[tsw]: testing_workers.html
[tsq]: testing_queues.html
[tsc]: testing_config.html

## Global Peer Module

Oban v2.11 introduced centralized leadership via Postgres tables. However,
Postgres based leadership isn't always a good fit. For example, an ephemeral
leadership mechanism is preferred for integration testing.

In that case, you can make use of the new `:global` powered peer module for
leadership:

```elixir
config :my_app, Oban,
  peer: Oban.Peers.Global,
  ...
```

## 2.12.0 — 2022-04-19

### Enhancements

- [Oban] Replace queue, plugin, and peer test configuration with a single
  `:testing` option. Now configuring Oban for testing only requires one change,
  setting the test mode to either `:inline` or `:manual`.

  - `:inline`—jobs execute immediately within the calling process and without
    touching the database. This mode is simple and may not be suitable for apps
    with complex jobs.
  - `:manual`—jobs are inserted into the database where they can be verified and
    executed when desired. This mode is more advanced and trades simplicity for
    flexibility.

- [Testing] Add `with_testing_mode/2` to temporarily change testing modes
  within the context of a function.

  Once the application starts in a particular testing mode it can't be changed.
  That's inconvenient if you're running in `:inline` mode and don't want a
  particular job to execute inline.

- [Config] Add `validate/1` to aid in testing dynamic Oban configuration.

- [Config] Validate full plugin and queue options on init, without the need
  to start plugins or queues.

- [Peers.Global] Add an alternate `:global` powered peer module.

- [Plugin] A new `Oban.Plugin` behaviour formalizes starting and validating
  plugins. The behaviour is implemented by all plugins, and is the foundation of
  enhanced config validation.

- [Plugin] Emit `[:oban, :plugin, :init]` event on init from every plugin.

### Bug Fixes

- [Executor ] Skip timeout check with an unknown worker

  When the worker can't be resolved we don't need to check the timeout. Doing so
  prevents returning a helpful "unknown worker" message, and instead causes a
  function error for `nil.timeout/1`.

- [Testing] Include `log` and `prefix` in generated conf for `perform_job`.

  The opts, and subsequent conf, built for `perform_job` didn't include the
  `prefix` or `log` options. That prevented functions that depend on a job's
  `conf` within `perform/1` from running with the correct options.

- [Drainer] Retain the currently configured engine while draining a queue.

- [Watchman] Skip pausing queues when shutdown is immediate. This prevents
  queue's from interacting with the database during short test runs.

For changes prior to v2.12 see the [v2.11][prv] docs.

[opc]: https://getoban.pro/docs/pro/changelog.html
[owc]: https://getoban.pro/docs/web/changelog.html
[prv]: https://hexdocs.pm/oban/2.11.2/changelog.html
