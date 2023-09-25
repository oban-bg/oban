# Changelog for Oban v2.15

_🌟 Looking for changes to Web or Pro? Check the [Oban.Pro Changelog][opc] or
the [Oban.Web Changelog][owc]. 🌟_

## 🐑 Oban Instance Module

New facade modules allow you to call `Oban` functions on instances with custom names, e.g. not
`Oban`, without passing a `t:Oban.name/0` as the first argument.

For example, rather than calling `Oban.config/1` you'd call `MyOban.config/0`:

```elixir
MyOban.config()
```

It also makes piping into Oban functions far more convenient: 

```elixir
%{some: :args}
|> MyWorker.new()
|> MyOban.insert()
```

## 🧩 Partial Matches in Testing Assertions

It's now possible to match a subset of fields on args or meta with `all_enqueued`,
`assert_enqueued`, and `refute_enqueued`. For example, the following assertion will now pass:

```elixir
# Given a job with these args: %{id: 123, mode: "active"}

assert_enqueued args: %{id: 123} #=> true
assert_enqueued args: %{mode: "active"} #=> true
assert_enqueued args: %{id: 321, mode: "active"} #=> false
```

The change applies to `args` and `meta` queries for `all_enqueued/2`, `assert_enqueued/2` and
`refute_enqueued/2` helpers.

## ⏲️ Unique Timestamp Option

Jobs are frequently scheduled for a time far in the future and it's often desirable for to
consider `scheduled` jobs for uniqueness, but unique jobs only checked the `:inserted_at`
timestamp.

Now `unique` has a `timestamp` option that allows checking the `:scheduled_at` timestamp instead:

```elixir
use Oban.Worker, unique: [period: 120, timestamp: :scheduled_at]
```

## v2.16.1 — 2023-09-25

### Bug Fixes

- [Testing] Restore splitting out all config options in helpers.

  Splitting all configuration keys is necessary when using `perform_job/3` with non-job options
  such as `:engine`.

## v2.16.0 — 2023-09-22

### Bug Fixes

- [Reindexer] Correct relname match for reindexer plugin

  We can safely assume all indexes start with `oban_jobs`. The previous pattern was based on an
  outdated index format from older migrations.

- [Testing] Support `repo`, `prefix`, and `log` query options in `use Oban.Testing`

For changes prior to v2.16 see the [v2.15][prv] docs.

[opc]: https://getoban.pro/docs/pro/changelog.html
[owc]: https://getoban.pro/docs/web/changelog.html
[prv]: https://hexdocs.pm/oban/2.15.2/changelog.html
