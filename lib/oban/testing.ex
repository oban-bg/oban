defmodule Oban.Testing do
  @moduledoc """
  This module simplifies making assertions about enqueued jobs during testing.

  Assertions may be made on any property of a job, but you'll typically want to check by `args`,
  `queue` or `worker`. If you're using namespacing through PostgreSQL schemas, also called
  "prefixes" in Ecto, you should use the `prefix` option when doing assertions about enqueued
  jobs during testing. By default the `prefix` option is `public`.

  ## Using in Tests

  The most convenient way to use `Oban.Testing` is to `use` the module:

      use Oban.Testing, repo: MyApp.Repo

  That will define three helper functions, `assert_enqueued/1,2`, `refute_enqueued/1,2` and
  `all_enqueued/1`. The functions can then be used to make assertions on the jobs that have been
  inserted in the database while testing.

  Some small examples:

  ```elixir
  # Assert that a job was already enqueued
  assert_enqueued worker: MyWorker, args: %{id: 1}

  # Assert that a job was enqueued or will be enqueued in the next 100ms
  assert_enqueued [worker: MyWorker, args: %{id: 1}], 100

  # Refute that a job was already enqueued
  refute_enqueued queue: "special", args: %{id: 2}

  # Refute that a job was already enqueued or would be enqueued in the next 100ms
  refute_enqueued queue: "special", args: %{id: 2}, 100

  # Make assertions on a list of all jobs matching some options
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
      |> Oban.insert!()
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

  ## Matching Scheduled Jobs and Timestamps

  In order to assert a job has been scheduled at a certain time, you will need to match against
  the `scheduled_at` attribute of the enqueued job.

      in_an_hour = DateTime.add(DateTime.utc_now(), 3600, :second)
      assert_enqueued worker: MyApp.Worker, scheduled_at: in_an_hour

  By default, Oban will apply a 1 second delta to all timestamp fields of jobs, so that small
  deviations between the actual value and the expected one are ignored. You may configure this
  delta by passing a tuple of value and a `delta` option (in seconds) to corresponding keyword:

      assert_enqueued worker: MyApp.Worker, scheduled_at: {in_an_hour, delta: 10}

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

  @wait_interval 10

  @doc false
  defmacro __using__(repo: repo) do
    quote do
      alias Oban.Testing

      def all_enqueued(opts) do
        Testing.all_enqueued(unquote(repo), opts)
      end

      def assert_enqueued(opts, timeout \\ :none) do
        if timeout == :none do
          Testing.assert_enqueued(unquote(repo), opts)
        else
          Testing.assert_enqueued(unquote(repo), opts, timeout)
        end
      end

      def refute_enqueued(opts, timeout \\ :none) do
        if timeout == :none do
          Testing.refute_enqueued(unquote(repo), opts)
        else
          Testing.refute_enqueued(unquote(repo), opts, timeout)
        end
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
    {prefix, opts} = extract_prefix(opts)

    opts
    |> base_query()
    |> order_by(desc: :id)
    |> repo.all(prefix: prefix)
  end

  @doc """
  Assert that a job with particular options has been enqueued.

  Only values for the provided arguments will be checked. For example, an assertion made on
  `worker: "MyWorker"` will match _any_ jobs for that worker, regardless of the queue or args.
  """
  @doc since: "0.3.0"
  @spec assert_enqueued(repo :: module(), opts :: Keyword.t()) :: true
  def assert_enqueued(repo, [_ | _] = opts) do
    error_message = """
    Expected a job matching:

    #{inspect(Map.new(opts), pretty: true)}

    to be enqueued. Instead found:

    #{inspect(available_jobs(repo, opts), pretty: true)}
    """

    assert get_job(repo, opts), error_message
  end

  @doc """
  Assert that a job with particular options is or will be enqueued within a timeout period.

  See `assert_enqueued/2` for additional details.

  ## Examples

  Assert that a job will be enqueued in the next 100ms:

      assert_enqueued [worker: MyWorker], 100
  """
  @doc since: "1.2.0"
  @spec assert_enqueued(repo :: module(), opts :: Keyword.t(), timeout :: pos_integer()) :: true
  def assert_enqueued(repo, [_ | _] = opts, timeout) when timeout > 0 do
    error_message = """
    Expected a job matching:

    #{inspect(Map.new(opts), pretty: true)}

    to be enqueued within #{timeout}ms
    """

    assert wait_for_job(repo, opts, timeout), error_message
  end

  @doc """
  Refute that a job with particular options has been enqueued.

  See `assert_enqueued/2` for additional details.
  """
  @doc since: "0.3.0"
  @spec refute_enqueued(repo :: module(), opts :: Keyword.t()) :: false
  def refute_enqueued(repo, [_ | _] = opts) do
    error_message = """
    Expected no jobs matching:

    #{inspect(opts, pretty: true)}

    to be enqueued
    """

    refute get_job(repo, opts), error_message
  end

  @doc """
  Refute that a job with particular options is or will be enqueued within a timeout period.

  The minimum refute timeout is 10ms.

  See `assert_enqueued/2` for additional details.

  ## Examples

  Refute that a job will not be enqueued in the next 100ms:

      refute_enqueued [worker: MyWorker], 100
  """
  @doc since: "1.2.0"
  @spec refute_enqueued(repo :: module(), opts :: Keyword.t(), timeout :: pos_integer()) :: false
  def refute_enqueued(repo, [_ | _] = opts, timeout) when timeout >= 10 do
    error_message = """
    Expected no jobs matching:

    #{inspect(opts, pretty: true)}

    to be enqueued within #{timeout}ms
    """

    refute wait_for_job(repo, opts, timeout), error_message
  end

  defp get_job(repo, opts) do
    {prefix, opts} = extract_prefix(opts)

    opts
    |> base_query()
    |> limit(1)
    |> select([:id])
    |> repo.one(prefix: prefix)
  end

  defp wait_for_job(repo, opts, timeout) when timeout > 0 do
    case get_job(repo, opts) do
      nil ->
        Process.sleep(@wait_interval)

        wait_for_job(repo, opts, timeout - @wait_interval)

      job ->
        job
    end
  end

  defp wait_for_job(_repo, _opts, _timeout), do: nil

  defp available_jobs(repo, opts) do
    {prefix, opts} = extract_prefix(opts)
    fields = Keyword.keys(opts)

    []
    |> base_query()
    |> select(^fields)
    |> repo.all(prefix: prefix)
    |> Enum.map(&Map.take(&1, fields))
  end

  defp base_query(opts) do
    {fields, field_opts} = Enum.map_reduce(opts, [], &extract_field_opts/2)

    fields_with_opts =
      fields
      |> normalize_fields()
      |> Enum.map(fn {key, value} ->
        {key, value, Keyword.get(field_opts, key, [])}
      end)

    Job
    |> where([j], j.state in ["available", "scheduled"])
    |> apply_where_clauses(fields_with_opts)
  end

  defp extract_prefix(opts) do
    Keyword.pop(opts, :prefix, "public")
  end

  defp extract_field_opts({key, {value, field_opts}}, field_opts_acc) do
    {{key, value}, [{key, field_opts} | field_opts_acc]}
  end

  defp extract_field_opts({key, value}, field_opts_acc) do
    {{key, value}, field_opts_acc}
  end

  defp normalize_fields(fields) do
    args = Keyword.get(fields, :args, %{})
    keys = Keyword.keys(fields)

    args
    |> Job.new(fields)
    |> Changeset.apply_changes()
    |> Map.from_struct()
    |> Map.take(keys)
    |> Keyword.new()
  end

  @timestamp_fields ~W(attempted_at completed_at inserted_at scheduled_at)a
  @timestamp_default_delta_seconds 1

  defp apply_where_clauses(query, []), do: query

  defp apply_where_clauses(query, [{key, value, opts} | rest]) when key in @timestamp_fields do
    delta = Keyword.get(opts, :delta, @timestamp_default_delta_seconds)

    window_start = DateTime.add(value, -delta, :second)
    window_end = DateTime.add(value, delta, :second)

    query
    |> where([j], fragment("? BETWEEN ? AND ?", field(j, ^key), ^window_start, ^window_end))
    |> apply_where_clauses(rest)
  end

  defp apply_where_clauses(query, [{key, value, _opts} | rest]) do
    query
    |> where(^[{key, value}])
    |> apply_where_clauses(rest)
  end
end
