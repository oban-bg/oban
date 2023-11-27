defmodule Oban.Testing do
  @moduledoc """
  This module simplifies testing workers and making assertions about enqueued jobs when testing in
  `:manual` mode.

  Assertions may be made on any property of a job, but you'll typically want to check by `args`,
  `queue` or `worker`.

  ## Usage

  The most convenient way to use `Oban.Testing` is to `use` the module:

      use Oban.Testing, repo: MyApp.Repo

  That will define the helper functions you'll use to make assertions on the jobs that should (or
  should not) be inserted in the database while testing.

  If you're using namespacing through Postgres schemas, also called "prefixes" in Ecto, you
  should set the `prefix` option:

      use Oban.Testing, repo: MyApp.Repo, prefix: "business"

  Unless overridden, the default `prefix` is `public`.

  ### Adding to Case Templates

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

  ## Examples

  After the test helpers are imported, you can make assertions about enqueued (available or
  scheduled) jobs in your tests.

  Here are a few examples that demonstrate what's possible:

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

  See the docs for `assert_enqueued/1,2`, `refute_enqueued/1,2`, and `all_enqueued/1` for more
  examples.

  ## Matching Timestamps

  In order to assert a job has been scheduled at a certain time, you will need to match against
  the `scheduled_at` attribute of the enqueued job.

      in_an_hour = DateTime.add(DateTime.utc_now(), 3600, :second)
      assert_enqueued worker: MyApp.Worker, scheduled_at: in_an_hour

  By default, Oban will apply a 1 second delta to all timestamp fields of jobs, so that small
  deviations between the actual value and the expected one are ignored. You may configure this
  delta by passing a tuple of value and a `delta` option (in seconds) to corresponding keyword:

      assert_enqueued worker: MyApp.Worker, scheduled_at: {in_an_hour, delta: 10}
  """

  @moduledoc since: "0.3.0"

  import ExUnit.Assertions, only: [assert: 2, refute: 2, flunk: 1]
  import Ecto.Query, only: [order_by: 2, select: 3, where: 2, where: 3]

  alias Ecto.Changeset

  alias Oban.{Config, Job, Queue.Executor, Repo, Worker}

  @type perform_opts :: Job.option() | Oban.option()

  @conf_keys []
             |> Config.new()
             |> Map.from_struct()
             |> Map.keys()

  @json_fields ~w(args meta)a
  @timestamp_fields ~w(attempted_at cancelled_at completed_at discarded_at inserted_at scheduled_at)a
  @wait_interval 10

  @doc false
  defmacro __using__(repo_opts) do
    repo_opts = Keyword.put_new(repo_opts, :prefix, false)

    unless Keyword.has_key?(repo_opts, :repo) do
      raise ArgumentError, "testing requires a :repo option to be set"
    end

    quote do
      alias Oban.Testing

      def perform_job(worker, args, opts \\ []) do
        opts = Keyword.merge(unquote(repo_opts), opts)

        Testing.perform_job(worker, args, opts)
      end

      def all_enqueued(opts \\ []) do
        unquote(repo_opts)
        |> Keyword.merge(opts)
        |> Testing.all_enqueued()
      end

      def assert_enqueued(opts, timeout \\ :none) do
        opts = Keyword.merge(unquote(repo_opts), opts)

        if timeout == :none do
          Testing.assert_enqueued(opts)
        else
          Testing.assert_enqueued(opts, timeout)
        end
      end

      def refute_enqueued(opts, timeout \\ :none) do
        opts = Keyword.merge(unquote(repo_opts), opts)

        if timeout == :none do
          Testing.refute_enqueued(opts)
        else
          Testing.refute_enqueued(opts, timeout)
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

    {conf_opts, opts} = Keyword.split(opts, @conf_keys)

    utc_now = DateTime.utc_now()

    changeset =
      args
      |> worker.new(opts)
      |> Changeset.put_change(:id, System.unique_integer([:positive]))
      |> Changeset.update_change(:args, &json_recode/1)
      |> Changeset.update_change(:meta, &json_recode/1)
      |> put_new_change(:attempt, 1)
      |> put_new_change(:attempted_at, utc_now)
      |> put_new_change(:scheduled_at, utc_now)
      |> put_new_change(:inserted_at, utc_now)

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
  @spec all_enqueued(opts :: Keyword.t()) :: [Job.t()]
  def all_enqueued(opts) when is_list(opts) do
    {conf, opts} = extract_conf(opts)

    filter_jobs(conf, opts)
  end

  @doc false
  @spec all_enqueued(repo :: module(), opts :: Keyword.t()) :: [Job.t()]
  def all_enqueued(repo, opts) do
    opts
    |> Keyword.put(:repo, repo)
    |> all_enqueued()
  end

  @doc """
  Assert that a job with matching fields is enqueued.

  Only values for the provided fields are checked. For example, an assertion made on `worker:
  "MyWorker"` will match _any_ jobs for that worker, regardless of every other field.

  ## Examples

  Assert that a job is enqueued for a certain worker and args:

      assert_enqueued worker: MyWorker, args: %{id: 1}

  Assert that a job is enqueued for a particular queue and priority:

      assert_enqueued queue: :business, priority: 3

  Assert that a job's args deeply match:

      assert_enqueued args: %{config: %{enabled: true}}

  Use the `:_` wildcard to assert that a job's meta has a key with any value:

      assert_enqueued meta: %{batch_id: :_}
  """
  @doc since: "0.3.0"
  @spec assert_enqueued(opts :: Keyword.t()) :: true
  def assert_enqueued([_ | _] = opts) do
    {conf, opts} = extract_conf(opts)

    if job_exists?(conf, opts) do
      true
    else
      flunk("""
      Expected a job matching:

      #{inspect_opts(opts)}

      to be enqueued. Instead found:

      #{inspect(available_jobs(conf, opts), charlists: :as_lists, pretty: true)}
      """)
    end
  end

  @doc false
  @spec assert_enqueued(repo :: module(), opts :: Keyword.t()) :: true
  def assert_enqueued(repo, opts) when is_list(opts) do
    opts
    |> Keyword.put(:repo, repo)
    |> assert_enqueued()
  end

  @doc """
  Assert that a job with particular options is or will be enqueued within a timeout period.

  See `assert_enqueued/1` for additional details.

  ## Examples

  Assert that a job will be enqueued in the next 100ms:

      assert_enqueued [worker: MyWorker], 100
  """
  @doc since: "1.2.0"
  @spec assert_enqueued(opts :: Keyword.t(), timeout :: timeout()) :: true
  def assert_enqueued([_ | _] = opts, timeout) when timeout > 0 do
    {conf, opts} = extract_conf(opts)

    error_message = """
    Expected a job matching:

    #{inspect_opts(opts)}

    to be enqueued within #{timeout}ms
    """

    assert wait_for_job(conf, opts, timeout), error_message
  end

  @doc false
  def assert_enqueued(repo, [_ | _] = opts, timeout) when timeout > 0 do
    opts
    |> Keyword.put(:repo, repo)
    |> assert_enqueued(timeout)
  end

  @doc """
  Refute that a job with particular options has been enqueued.

  See `assert_enqueued/1` for additional details.

  ## Examples

  Refute that a job is enqueued for a certain worker:

      refute_enqueued worker: MyWorker

  Refute that a job is enqueued for a certain worker and args:

      refute_enqueued worker: MyWorker, args: %{id: 1}

  Refute that a job's nested args match:

      refute_enqueued args: %{config: %{enabled: false}}

  Use the `:_` wildcard to refute that a job's meta has a key with any value:

      refute_enqueued meta: %{batch_id: :_}
  """
  @doc since: "0.3.0"
  @spec refute_enqueued(opts :: Keyword.t()) :: false
  def refute_enqueued([_ | _] = opts) do
    {conf, opts} = extract_conf(opts)

    error_message = """
    Expected no jobs matching:

    #{inspect_opts(opts)}

    to be enqueued.
    """

    refute job_exists?(conf, opts), error_message
  end

  @doc false
  def refute_enqueued(repo, [_ | _] = opts) do
    opts
    |> Keyword.put(:repo, repo)
    |> refute_enqueued()
  end

  @doc """
  Refute that a job with particular options is or will be enqueued within a timeout period.

  See `assert_enqueued/1` for additional details.

  ## Examples

  Refute that a job will be enqueued in the next 100ms:

      refute_enqueued [worker: MyWorker], 100
  """
  @doc since: "1.2.0"
  @spec refute_enqueued(opts :: Keyword.t(), timeout :: timeout()) :: false
  def refute_enqueued([_ | _] = opts, timeout) when is_integer(timeout) do
    {conf, opts} = extract_conf(opts)

    error_message = """
    Expected no jobs matching:

    #{inspect_opts(opts)}

    to be enqueued within #{timeout}ms
    """

    refute wait_for_job(conf, opts, timeout), error_message
  end

  def refute_enqueued(repo, [_ | _] = opts, timeout) do
    opts
    |> Keyword.put(:repo, repo)
    |> refute_enqueued(timeout)
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
  @spec with_testing_mode(:inline | :manual, (-> any())) :: any()
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
    |> inspect(charlists: :as_lists, pretty: true)
  end

  # Perform Helpers

  defp put_new_change(changeset, key, value) do
    case Changeset.fetch_change(changeset, key) do
      {:ok, _} ->
        changeset

      :error ->
        Changeset.put_change(changeset, key, value)
    end
  end

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

  defp json_recode(map) do
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

  defp extract_conf(opts) do
    {conf_opts, opts} = Keyword.split(opts, @conf_keys)

    {Config.new(conf_opts), opts}
  end

  defp job_exists?(conf, opts) do
    conf
    |> filter_jobs(opts)
    |> Enum.any?()
  end

  defp wait_for_job(conf, opts, timeout) when timeout > 0 do
    if job_exists?(conf, opts) do
      true
    else
      Process.sleep(@wait_interval)

      wait_for_job(conf, opts, timeout - @wait_interval)
    end
  end

  defp wait_for_job(_conf, _opts, _timeout), do: false

  defp available_jobs(conf, opts) do
    query =
      []
      |> base_query()
      |> select([j], map(j, ^Keyword.keys(opts)))

    Repo.all(conf, query)
  end

  defp base_query(opts) do
    query =
      Job
      |> where([j], j.state in ["available", "scheduled"])
      |> order_by(desc: :id)

    opts
    |> Keyword.drop(~w(args meta)a)
    |> Enum.reduce(query, &conditions/2)
  end

  defp conditions({:queue, queue}, query), do: where(query, queue: ^to_string(queue))
  defp conditions({:state, state}, query), do: where(query, state: ^to_string(state))
  defp conditions({:worker, worker}, query), do: where(query, worker: ^Worker.to_string(worker))

  defp conditions({key, val}, query) when key in @timestamp_fields do
    {time, delta} =
      case val do
        {time, delta: delta} -> {time, delta}
        time -> {time, 1}
      end

    {:ok, time} = Ecto.Type.cast(:utc_datetime, time)

    begin = DateTime.add(time, -delta, :second)
    until = DateTime.add(time, +delta, :second)

    where(query, [j], fragment("? BETWEEN ? AND ?", field(j, ^key), ^begin, ^until))
  end

  defp conditions({key, value}, query), do: where(query, ^[{key, value}])

  defp filter_jobs(conf, opts) do
    {json_opts, base_opts} = Keyword.split(opts, @json_fields)

    json_opts = Keyword.new(json_opts, fn {key, val} -> {key, json_recode(val)} end)

    conf
    |> Repo.all(base_query(base_opts))
    |> Enum.filter(fn job -> Enum.all?(json_opts, &contains?(&1, job)) end)
  end

  defp contains?({key, "_"}, data) when is_map_key(data, key), do: true

  defp contains?({key, val}, data) when is_map(val) do
    case Map.get(data, key) do
      nil -> false
      sub -> Enum.all?(val, &contains?(&1, sub))
    end
  end

  defp contains?({key, val}, data), do: Map.get(data, key) == val
end
