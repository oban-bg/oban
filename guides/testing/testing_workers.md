# Testing Workers

Worker modules are the primary "unit" of an Oban system. You can (and should)
test a worker's callback functions locally, in-process, without touching the
database.

Most worker callback functions take a single argument: an `Oban.Job` struct. A
job encapsulates arguments, metadata, and other options. Creating jobs, and
verifying that they're built correctly, requires some boilerplate...that's where
`Oban.Testing.perform_job/3` comes in!

## Testing Perform

The `perform_job/3` helper reduces boilerplate when constructing jobs for unit
tests and checks for common pitfalls. For example, it automatically converts
`args` to string keys before calling `perform/1`, ensuring that perform clauses
aren't erroneously trying to match on atom keys.

Let's work through test-driving a worker to demonstrate.

Start by defining a test that creates a user and then use `perform_job` to
manually call an account activation worker. In this context "activation" could
mean sending an email, notifying administrators, or any number of
business-critical functions—what's important is how we're testing it.

```elixir
defmodule MyApp.ActivationWorkerTest do
  use MyApp.Case, async: true

  test "activating a new user" do
    user = MyApp.User.create(email: "parker@example.com")

    {:ok, _user} = perform_job(MyApp.ActivationWorker, %{id: user.id})
  end
end
```

Running the test at this point will raise an error that explains the module
doesn't implement the `Oban.Worker` behaviour.

```text
1) test activating a new account (MyApp.ActivationWorkerTest)

   Expected worker to be a module that implements the Oban.Worker behaviour, got:

   MyApp.ActivationWorker

   code: {:ok, user} = perform_job(MyApp.ActivationWorker, %{id: user.id})
```

To fix it, define a worker module with the appropriate signature and return
value:

```elixir
defmodule MyApp.ActivationWorker do
  use Oban.Worker

  @impl Worker
  def perform(%Job{args: %{"id" => user_id}}) do
    MyApp.Account.activate(user_id)
  end
end
```

The `perform_job/3` helper's errors will guide you through implementing a
complete worker with the following assertions:

* That the worker implements the `Oban.Worker` behaviour
* That `args` is encodable/decodable to JSON and always has string keys
* That the options provided build a valid job
* That the return value is expected, e.g. `:ok`, `{:ok, value}`, `{:error, value}` etc.
* That a custom `new/1,2` callback works properly

If all of the assertions pass, then you'll get the result of `perform/1` for you
to make additional assertions on.

## Testing Other Callbacks

You may wish to test less-frequently used worker callbacks such as `backoff/1`
and `timeout/1`, but those callbacks don't have dedicated testing helpers.
Never fear, it's adequate to build a job struct and test callbacks directly!

Here's a sample test that asserts the backoff value is simply two-times the
job's `attempt`:

```elixir
test "calculating custom backoff as a multiple of job attempts" do
  assert 2 == MyWorker.backoff(%Oban.Job{attempt: 1})
  assert 4 == MyWorker.backoff(%Oban.Job{attempt: 2})
  assert 6 == MyWorker.backoff(%Oban.Job{attempt: 3})
end
```

Similarly, here's a sample that verifies a `timeout/1` callback always returns
some number of milliseconds:

```elixir
test "allowing a multiple of the attempt as job timeout" do
  assert 1000 == MyWorker.timeout(%Oban.Job{attempt: 1})
  assert 2000 == MyWorker.timeout(%Oban.Job{attempt: 2})
end
```

Jobs are Ecto schemas, and therefore structs. There isn't anything magical about
them! Explore the `Oban.Job` documentation to see all of the types and fields
available for testing.
