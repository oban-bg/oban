defmodule Oban.Testing do
  @moduledoc """
  This module simplifies making assertions about enqueued jobs during testing.

  Assertions may be made on any property of a job, but you'll typically want to check by `args`,
  `queue` or `worker`.

  ## Using in Tests

  The most convenient way to use `Oban.Testing` is to `use` the module:

      use Oban.Testing, repo: MyApp.Repo

  That will define three helper functions, `assert_enqueued/1`, `refute_enqueued/1` and
  `all_enqueued/1`. The functions can then be used to make assertions on the jobs that have been
  inserted in the database while testing.

  ```elixir
  assert_enqueued worker: MyWorker, args: %{id: 1}

  # or

  refute_enqueued queue: "special", args: %{id: 2}

  # or

  assert [%{args: %{"id" => 1}}] = all_enqueued(worker: MyWorker)
  ```

  Note that the final example, using `all_enqueued/1`, returns a raw list of matching jobs and
  does not make an assertion by itself. This makes it possible to test using pattern matching at
  the expense of being more verbose.

  ## Example

  Given a simple module that enqueues a job:

  ```elixir
  defmodule MyApp.Business do
    def work(args) do
      args
      |> Oban.Job.new(worker: MyApp.Worker, queue: :special)
      |> MyApp.Repo.insert!()
    end
  end
  ```

  The behaviour can be exercised in your test code:

      defmodule MyApp.BusinessTest do
        use ExUnit.Case, async: true
        use Oban.Testing, repo: MyApp.Repo

        alias MyApp.Business

        test "jobs are enqueued with provided arguments" do
          Business.work(%{id: 1, message: "Hello!"})

          assert_enqueued worker: MyApp.Worker, args: %{id: 1, message: "Hello!"}
        end
      end

  ## Adding to Case Templates

  To include helpers in all of your tests you can add it to your case template:

  ```elixir
  defmodule MyApp.DataCase do
    use ExUnit.CaseTemplate

    using do
      quote do
        use Oban.Testing, repo: MyApp.Repo

        import Ecto
        import Ecto.Changeset
        import Ecto.Query
        import MyApp.DataCase

        alias MyApp.Repo
      end
    end
  end
  ```
  """
  @moduledoc since: "0.3.0"

  import ExUnit.Assertions, only: [assert: 2, refute: 2]
  import Ecto.Query, only: [limit: 2, order_by: 2, select: 2, where: 2, where: 3]

  alias Ecto.Changeset
  alias Oban.Job

  @doc false
  defmacro __using__(repo: repo) do
    quote do
      alias Oban.Testing

      def all_enqueued(opts) do
        Testing.all_enqueued(unquote(repo), opts)
      end

      def assert_enqueued(opts) do
        Testing.assert_enqueued(unquote(repo), opts)
      end

      def refute_enqueued(opts) do
        Testing.refute_enqueued(unquote(repo), opts)
      end
    end
  end

  @doc """
  Retrieve all currently enqueued jobs matching a set of options.

  Only jobs matching all of the provided arguments will be returned. Additionally, jobs are
  returned in descending order where the most recently enqueued job will be listed first.

  ## Examples

  Assert based on only _some_ of a job's args:

      assert [%{args: %{"id" => 1}}] = all_enqueued(worker: MyWorker)

  Assert that exactly one job was inserted for a queue:

      assert [%Oban.Job{}] = all_enqueued(queue: :alpha)
  """
  @doc since: "0.6.0"
  @spec all_enqueued(repo :: module(), opts :: Keyword.t()) :: [Job.t()]
  def all_enqueued(repo, [_ | _] = opts) do
    opts
    |> base_query()
    |> order_by(desc: :id)
    |> repo.all()
  end

  @doc """
  Assert that a job with particular options has been enqueued.

  Only values for the provided arguments will be checked. For example, an assertion made on
  `worker: "MyWorker"` will match _any_ jobs for that worker, regardless of the queue or args.
  """
  @doc since: "0.3.0"
  @spec assert_enqueued(repo :: module(), opts :: Keyword.t()) :: true
  def assert_enqueued(repo, [_ | _] = opts) do
    assert get_job(repo, opts),
           "Expected a job matching #{inspect(opts)} to be enqueued. Found: #{
             inspect(available_jobs(repo, opts))
           }"
  end

  @doc """
  Refute that a job with particular options has been enqueued.

  See `assert_enqueued/2` for additional details.
  """
  @doc since: "0.3.0"
  @spec refute_enqueued(repo :: module(), opts :: Keyword.t()) :: false
  def refute_enqueued(repo, [_ | _] = opts) do
    refute get_job(repo, opts), "Expected no jobs matching #{inspect(opts)} to be enqueued"
  end

  defp get_job(repo, opts) do
    opts
    |> base_query()
    |> limit(1)
    |> select([:id])
    |> repo.one()
  end

  defp available_jobs(repo, opts) do
    fields = Keyword.keys(opts)

    base_query([])
    |> select(^fields)
    |> repo.all()
    |> Enum.map(&Map.take(&1, fields))
  end

  defp base_query(opts) do
    Job
    |> where([j], j.state in ["available", "scheduled"])
    |> where(^normalize_opts(opts))
  end

  defp normalize_opts(opts) do
    args = Keyword.get(opts, :args, %{})
    keys = Keyword.keys(opts)

    args
    |> Job.new(opts)
    |> Changeset.apply_changes()
    |> Map.from_struct()
    |> Map.take(keys)
    |> Keyword.new()
  end
end
