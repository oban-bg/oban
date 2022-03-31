# Introduction to Testing

Automated testing is an essential component of building reliable, long-lived
applications. Oban orchestrates your application's background tasks, so naturally,
testing Oban is highly recommended.

## Setup Application Config

Ensure your app is configured for testing before you start running any tests.
Chances are, you already did this as part of the initial setup, but just to be
sure disable running queues and plugins within `test.exs`:

```elixir
config :my_app, Oban, queues: false, plugins: false
```

Disabling with `false` prevents Oban from running any queries in the background.
This simultaneously prevents Sandbox errors (`DBConnection.OnwershipError`) from
plugin queries and gives you complete control over when jobs run.

Note that you must use `false` because configuration is deep-merged and using an
empty list like `queues: []` won't have any effect.

## Setup Testing Helpers

Oban provides some helpers to facilitate testing. These helpers handle the
boilerplate of making assertions on which jobs are enqueued.

The most convenient way to use the helpers is to `use` the module within your
test case:

```elixir
defmodule MyApp.Case do
  use ExUnit.CaseTemplate

  using do
    quote do
      use Oban.Testing, repo: MyApp.Repo
    end
  end
end
```

Alternatively, you can `use` the testing module in individual tests if you'd
prefer not to include helpers in _every_ test.

```elixir
defmodule MyApp.WorkerTest do
  use MyApp.Case, async: true

  use Oban.Testing, repo: MyApp.Repo
end
```

Either way, using requires the `repo` option because it's injected into many of
the generated helpers.

If you are using isolation with namespaces through PostgreSQL schemas (Ecto
"prefixes"), you can also specify this prefix when using `Oban.Testing`:

```elixir
use Oban.Testing, repo: MyApp.Repo, prefix: "private"
```

With Oban configured for testing and helpers in the appropriate places, you're
ready for testing. Learn about unit testing with [Testing Workers][tw],
integration testing with [Testing Queues][tq], or prepare for production with
[Testing Config][tc].

[tw]: testing_workers.html
[tq]: testing_queues.html
[tc]: testing_config.html
