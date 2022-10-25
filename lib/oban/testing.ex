defmodule Oban.Testing do
  @moduledoc """
  This module simplifies testing workers and making assertions about enqueued jobs when testing in
  `:manual` mode.

  Assertions may be made on any property of a job, but you'll typically want to check by `args`,
  `queue` or `worker`. If you're using namespacing through PostgreSQL schemas, also called
  "prefixes" in Ecto, you should use the `prefix` option when doing assertions about enqueued
  jobs during testing. By default the `prefix` option is `public`.

  ## Using in Tests

  The most convenient way to use `Oban.Testing` is to `use` the module:

      use Oban.Testing, repo: MyApp.Repo

  That will define the helper functions you'll use to make assertions on the jobs that should (or
  should not) be inserted in the database while testing.

  Along with the `repo` you can also specify an alternate prefix to use in all assertions:

      use Oban.Testing, repo: MyApp.Repo, prefix: "business"

  Some example assertions:

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

  # Assert that no jobs are enqueued in any queues
  assert [] = all_enqueued()
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

  alias Oban.{Config, Job, Queue.Executor, Repo, Worker}

  @type perform_opts ::
          Job.option()
          | {:log, Logger.level()}
          | {:prefix, binary()}
          | {:repo, module()}

  @wait_interval 10

  @doc false
  defmacro __using__(opts) do
    repo = Keyword.fetch!(opts, :repo)
    prefix = Keyword.get(opts, :prefix, "public")

    quote do
      alias Oban.Testing

      def perform_job(worker, args, opts \\ []) do
        opts =
          opts
          |> Keyword.put_new(:repo, unquote(repo))
          |> Keyword.put_new(:prefix, unquote(prefix))

        Testing.perform_job(worker, args, opts)
      end

      def all_enqueued(opts \\ []) do
        opts = Keyword.put_new(opts, :prefix, unquote(prefix))

        Testing.all_enqueued(unquote(repo), opts)
      end

      def assert_enqueued(opts, timeout \\ :none) do
        opts = Keyword.put_new(opts, :prefix, unquote(prefix))

        if timeout == :none do
          Testing.assert_enqueued(unquote(repo), opts)
        else
          Testing.assert_enqueued(unquote(repo), opts, timeout)
        end
      end

      def refute_enqueued(opts, timeout \\ :none) do
        opts = Keyword.put_new(opts, :prefix, unquote(prefix))

        if timeout == :none do
          Testing.refute_enqueued(unquote(repo), opts)
        else
          Testing.refute_enqueued(unquote(repo), opts, timeout)
        end
      end
    end
  end

  @doc """
  Construct a job and execute it with a worker module.

  This reduces boilerplate when constructing jobs for unit tests and checks for common pitfalls.
  For example, it automatically converts `args` to string keys before calling `perform/1`,
  ensuring that perform clauses aren't erroneously trying to match atom keys.

  The helper makes the following assertions:

  * That the worker implements the `Oban.Worker` behaviour
  * That the options provided build a valid job
  * That the return is valid, e.g. `:ok`, `{:ok, value}`, `{:error, value}` etc.

  If all of the assertions pass then the function returns the result of `perform/1` for you to
  make additional assertions on.

  ## Examples

  Successfully execute a job with some string arguments:

      assert :ok = perform_job(MyWorker, %{"id" => 1})

  Successfully execute a job and assert that it returns an error tuple:

      assert {:error, _} = perform_job(MyWorker, %{"bad" => "arg"})

  Execute a job with the args keys automatically stringified:

      assert :ok = perform_job(MyWorker, %{id: 1})

  Exercise custom attempt handling within a worker by passing options:

      assert :ok = perform_job(MyWorker, %{}, attempt: 42)

  Cause a test failure because the provided worker isn't real:

      assert :ok = perform_job(Vorker, %{"id" => 1})
  """
  @doc since: "2.0.0"
  @spec perform_job(worker :: Worker.t(), args :: term(), [perform_opts()]) :: Worker.result()
  def perform_job(worker, args, opts) when is_atom(worker) do
    assert_valid_worker(worker)

    {conf_opts, opts} = Keyword.split(opts, [:log, :prefix, :repo])

    opts =
      opts
      |> Keyword.put_new(:attempt, 1)
      |> Keyword.put_new(:attempted_at, DateTime.utc_now())
      |> Keyword.put_new(:scheduled_at, DateTime.utc_now())
      |> Keyword.put_new(:inserted_at, DateTime.utc_now())

    changeset =
      args
      |> worker.new(opts)
      |> Changeset.put_change(:id, System.unique_integer([:positive]))
      |> Changeset.update_change(:args, &json_encode_decode/1)
      |> Changeset.update_change(:meta, &json_encode_decode/1)

    assert_valid_changeset(changeset)

    job = Changeset.apply_action!(changeset, :insert)

    result =
      conf_opts
      |> Config.new()
      |> Executor.new(job, safe: false, ack: false)
      |> Executor.call()
      |> Map.fetch!(:result)

    assert_valid_result(result)

    result
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

  Assert that there aren't any jobs enqueued for any queues or workers:

      assert [] = all_enqueued()
  """
  @doc since: "0.6.0"
  @spec all_enqueued(repo :: module(), opts :: Keyword.t()) :: [Job.t()]
  def all_enqueued(repo, opts) when is_list(opts) do
    {conf, opts} = extract_conf(repo, opts)

    Repo.all(conf, base_query(opts))
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

    #{inspect_opts(opts)}

    to be enqueued in the #{inspect(opts[:prefix])} schema. Instead found:

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

    #{inspect_opts(opts)}

    to be enqueued in the #{inspect(opts[:prefix])} schema within #{timeout}ms
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

    #{inspect_opts(opts)}

    to be enqueued in the #{inspect(opts[:prefix])} schema
    """

    refute get_job(repo, opts), error_message
  end

  @doc """
  Refute that a job with particular options is or will be enqueued within a timeout period.

  The minimum refute timeout is 10ms.

  See `assert_enqueued/2` for additional details.

  ## Examples

  Refute that a job will be enqueued in the next 100ms:

      refute_enqueued [worker: MyWorker], 100
  """
  @doc since: "1.2.0"
  @spec refute_enqueued(repo :: module(), opts :: Keyword.t(), timeout :: pos_integer()) :: false
  def refute_enqueued(repo, [_ | _] = opts, timeout) when timeout >= 10 do
    error_message = """
    Expected no jobs matching:

    #{inspect_opts(opts)}

    to be enqueued in the #{inspect(opts[:prefix])} schema within #{timeout}ms
    """

    refute wait_for_job(repo, opts, timeout), error_message
  end

  @doc """
  Change the testing mode within the context of a function.

  Only `:manual` and `:inline` mode are supported, as `:disabled` implies that supervised queues
  and plugins are running and this function won't start any processes.

  ## Examples

  Switch to `:manual` mode when an Oban instance is configured for `:inline` testing:

      Oban.Testing.with_testing_mode(:manual, fn ->
        Oban.insert(MyWorker.new(%{id: 123}))

        assert_enqueued worker: MyWorker, args: %{id: 123}
      end)

  Visa-versa, switch to `:inline` mode:

      Oban.Testing.with_testing_mode(:inline, fn ->
        {:ok, %Job{state: "completed"}} = Oban.insert(MyWorker.new(%{id: 123}))
      end)
  """
  @doc since: "2.12.0"
  @spec with_testing_mode(:inline | :manual, (() -> any())) :: any()
  def with_testing_mode(mode, fun) when mode in [:manual, :inline] and is_function(fun, 0) do
    Process.put(:oban_testing, mode)

    fun.()
  after
    Process.delete(:oban_testing)
  end

  # Assert Helpers

  defp inspect_opts(opts) do
    opts
    |> Map.new()
    |> Map.drop([:prefix])
    |> inspect(pretty: true)
  end

  # Perform Helpers

  defp assert_valid_worker(worker) do
    assert Code.ensure_loaded?(worker) and implements_worker?(worker), """
     Expected worker to be a module that implements the Oban.Worker behaviour, got:

    #{inspect(worker)}
    """
  end

  defp implements_worker?(worker) do
    :attributes
    |> worker.__info__()
    |> Keyword.get_values(:behaviour)
    |> List.flatten()
    |> Enum.member?(Oban.Worker)
  end

  defp assert_valid_changeset(changeset) do
    assert changeset.valid?, """
    Expected args and opts to build a valid job, got validation errors:

    #{traverse_errors(changeset)}
    """
  end

  defp traverse_errors(changeset) do
    traverser = fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end

    changeset
    |> Changeset.traverse_errors(traverser)
    |> Enum.map_join("\n", fn {key, val} -> "#{key}: #{val}" end)
  end

  defp json_encode_decode(map) do
    map
    |> Jason.encode!()
    |> Jason.decode!()
  end

  defp assert_valid_result(result) do
    valid? =
      case result do
        :ok -> true
        {:ok, _value} -> true
        {:cancel, _value} -> true
        {:error, _value} -> true
        {:discard, _value} -> true
        {:snooze, snooze} when is_integer(snooze) -> true
        :discard -> true
        _ -> false
      end

    assert valid?, """
    Expected result to be one of

      - `:ok`
      - `{:ok, value}`
      - `{:cancel, reason}`
      - `{:error, reason}`
      - `{:snooze, duration}

    Instead received:

    #{inspect(result, pretty: true)}
    """
  end

  # Enqueued Helpers

  defp get_job(repo, opts) do
    {conf, opts} = extract_conf(repo, opts)

    Repo.one(conf, opts |> base_query() |> limit(1) |> select([:id]))
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
    {conf, opts} = extract_conf(repo, opts)

    fields = Keyword.keys(opts)

    conf
    |> Repo.all([] |> base_query() |> select(^fields))
    |> Enum.map(&Map.take(&1, fields))
  end

  defp base_query(opts) do
    fields_with_opts = normalize_fields(opts)

    Job
    |> where([j], j.state in ["available", "scheduled"])
    |> apply_where_clauses(fields_with_opts)
    |> order_by(desc: :id)
  end

  defp extract_conf(repo, opts) do
    {conf_opts, opts} = Keyword.split(opts, [:prefix])

    conf =
      conf_opts
      |> Keyword.put(:repo, repo)
      |> Config.new()

    {conf, opts}
  end

  defp extract_field_opts({key, {value, field_opts}}, field_opts_acc) do
    {{key, value}, [{key, field_opts} | field_opts_acc]}
  end

  defp extract_field_opts({key, value}, field_opts_acc) do
    {{key, value}, field_opts_acc}
  end

  defp normalize_fields(opts) do
    {fields, field_opts} = Enum.map_reduce(opts, [], &extract_field_opts/2)

    args = Keyword.get(fields, :args, %{})
    keys = Keyword.keys(fields)

    args
    |> Job.new(fields)
    |> Changeset.apply_changes()
    |> Map.from_struct()
    |> Map.take(keys)
    |> Enum.map(fn {key, value} -> {key, value, Keyword.get(field_opts, key, [])} end)
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
