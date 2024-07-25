# Testing Queues

Where workers are the primary "unit" of an Oban system, queues are the
"integration" point between the database and your application. That means to
test queues and the jobs within them, your tests will have to interact with the
database. To simplify that interaction, reduce boilerplate, and make assertions
more expressive `Oban.Testing` provides a variety of helpers.

## Asserting Enqueued Jobs

During test runs you don't typically want to execute jobs. Rather, you need
to verify that the job was enqueued properly. With the recommended test setup
queues and plugins are disabled, and jobs won't be inserted into the database at all.
Instead, they'll be executed immediately within the calling process.
The `Oban.Testing.assert_enqueued/2` and `Oban.Testing.refute_enqueued/2` helpers
simplify running queries to check for those `available` or `scheduled` jobs
sitting in the database.

Let's look at an example where we want to check that an activation job is
enqueued after a user signs up:

```elixir
test "scheduling activation upon sign up" do
  {:ok, account} = MyApp.Account.sign_up(email: "parker@example.com")

  assert_enqueued worker: MyApp.ActivationWorker, args: %{id: account.id}, queue: :default
end
```

Likewise, we can also refute that a job was enqueued. The `refute_enqueued`
helper takes the same arguments as `assert_enqueued`, though you should take
care to be as unspecific as possible.

Building on the example above, let's refute that a job is enqueued when account
sign up fails:

```elixir
test "bypassing activation when sign up fails" do
  {:error, _reason} = MyApp.Account.sign_up(email: "parker@example.com")

  refute_enqueued worker: MyApp.ActivationWorker
end
```

## Asserting Multiple Jobs

Asserting and refuting about a single job isn't always enough. Sometimes you
need to check for multiple jobs at once, or perform more complex assertions on
the jobs themselves. In that situation, you can use `all_enqueued` instead.

The first example we'll look at asserts that multiple jobs from the same worker are
enqueued all at once:

```elixir
test "enqueuing one job for each child record" do
  :ok = MyApp.Account.notify_owners(account())

  assert jobs = all_enqueued(worker: MyApp.NotificationWorker)
  assert 3 == length(jobs)
end
```

The `enqueued` helpers all build dynamic queries to check for jobs within the
database. Dynamic queries don't work for complex objects with nested values or a
partial set of keys. In that case, you can use `all_enqueued` to pull jobs into
your tests and use the full power of pattern matching for assertions.

```elixir
test "enqueued jobs have args that match a particular pattern" do
  :ok = MyApp.Account.notify_owners(account())

  for job <- all_enqueued(queue: :default) do
    assert %{"email" => _, "avatar" => %{"url" => _}} = job.args
  end
end
```

## Integration Testing Queues

During integration tests it may be necessary to run jobs because they do work
essential for the test to complete, i.e. sending an email, processing media,
etc. You can execute all available jobs in a particular queue by calling
`Oban.drain_queue/1,2` directly from your tests.

For example, to process all pending jobs in the "mailer" queue while testing
some business logic:

```elixir
defmodule MyApp.BusinessTest do
  use MyApp.DataCase, async: true

  alias MyApp.{Business, Worker}

  test "we stay in the business of doing business" do
    :ok = Business.schedule_a_meeting(%{email: "monty@brewster.com"})

    assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :mailer)

    # Now, make an assertion about the email delivery
  end
end
```

See `Oban.drain_queue/1,2` for a myriad of options and additional details.
