# Contributing

Thanks for your interest in Oban. A few notes before opening a PR.

## Scope

Oban is a focused job processing library, and most of the design and roadmap work happens
internally. We are selective about accepting external contributions; meaningful changes that
aren't first discussed in an issue may be declined regardless of quality. Please open an issue
describing the change and wait for a maintainer's response before starting work.

## Bug reports

File a [GitHub issue](https://github.com/oban-bg/oban/issues) with:

- Oban, Elixir, Erlang/OTP, and Postgres/SQLite versions
- A minimal reproduction (a script or a small repo is ideal)
- The full stacktrace and any relevant log output

For security issues, see [SECURITY.md](./SECURITY.md), do not open a public issue.

## Pull requests

- Open an issue first for anything beyond a typo, formatting, or one-line fix.
- Run `mix test.ci` to check formatting, lint, and run the test suite locally.
- New behavior needs tests; bug fixes need a regression test.
- Keep PRs focused — one change per PR.
- Documentation changes that rephrase existing prose without adding new information will generally
  be declined.

## Contributor License Agreement

By submitting a pull request, you agree that your contribution is licensed under the project's
then-current LICENSE and that Soren, LLC may relicense your contribution under different terms
in the future.

## Development

See the README for setup. Tests assume a local Postgres; see `test/test_helper.exs` for
configuration.

### Running databases with Docker

If you'd rather not install Postgres and MySQL on your machine, a `compose.yaml` is included to
spin up both in containers:

```bash
docker compose up -d   # start postgres and mysql
mix test.setup         # create and migrate the test databases
mix test.ci            # format check, lint, and run the suite
docker compose down    # stop the containers when you're done
```

The containers match the versions used in CI and expose the default ports, so the connection URLs
in `test/test_helper.exs` work without any extra configuration.
