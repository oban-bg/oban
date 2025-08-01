defmodule Oban.TestingTest do
  use Oban.Case, async: true

  use Oban.Testing, repo: Oban.Test.Repo, log: false

  alias Oban.{TelemetryHandler, Testing}

  defmodule InvalidWorker do
    def perform(_), do: :ok
  end

  defmodule OverriddenWorker do
    use Oban.Worker

    @impl Worker
    def new({key, val}, _) do
      super(%{key => val}, [])
    end

    @impl Worker
    def perform(%{args: args}) do
      {:ok, args}
    end
  end

  defmodule MyApp.Worker do
    defmacro __using__(_opts) do
      quote do
        @behaviour unquote(__MODULE__)
      end
    end

    @callback process() :: :ok
  end

  defmodule DoubleBehaviourWorker do
    use MyApp.Worker
    use Oban.Worker

    @impl Oban.Worker
    def perform(_job), do: :ok

    @impl MyApp.Worker
    def process, do: :ok
  end

  defmodule MisbehavedWorker do
    use Oban.Worker

    @impl Oban.Worker
    def perform(%{args: %{"action" => "bad_atom"}}), do: :bad
    def perform(%{args: %{"action" => "bad_string"}}), do: "bad"
    def perform(%{args: %{"action" => "bad_error"}}), do: :error
    def perform(%{args: %{"action" => "bad_tuple"}}), do: {:ok, "bad", :bad}
    def perform(%{args: %{"action" => "bad_snooze"}}), do: {:snooze, true}
    def perform(%{args: %{"action" => "bad_code"}}), do: raise(RuntimeError, "bad")
    def perform(%{args: %{"action" => "bad_timing"}}), do: Process.sleep(10)

    @impl Oban.Worker
    def timeout(%{args: %{"timeout" => timeout}}), do: timeout
    def timeout(_job), do: :infinity
  end

  defmodule AttemptDrivenWorker do
    use Oban.Worker

    @impl Oban.Worker
    def perform(%{attempt: attempt}) do
      {:ok, attempt}
    end
  end

  defmodule TemporalWorker do
    use Oban.Worker

    @impl Oban.Worker
    def perform(%Oban.Job{} = job) do
      {:ok, Map.take(job, ~w(attempted_at inserted_at scheduled_at)a)}
    end
  end

  defmodule EchoWorker do
    use Oban.Worker

    @impl Oban.Worker
    def perform(%{args: %{"field" => field}} = job) do
      field = String.to_existing_atom(field)

      {:ok, Map.fetch!(job, field)}
    end
  end

  describe "build_job/3" do
    test "creating a valid job changeset out of the args and options" do
      job = build_job(Worker, %{id: 1}, meta: %{foo: "bar"})

      assert %{args: args, id: id, meta: meta, worker: "Oban.Integration.Worker"} = job

      assert is_integer(id)
      assert %{"id" => 1} = args
      assert %{"foo" => "bar"} = meta
    end
  end

  describe "perform_job/1,2" do
    test "executing a job created with build_job/3" do
      assert {:ok, %{"foo" => "bar"}} =
               EchoWorker
               |> build_job(%{field: :meta}, meta: %{foo: "bar"})
               |> perform_job()

      assert {:ok, %{"foo" => "bar"}} =
               EchoWorker
               |> build_job(%{field: :meta}, meta: %{foo: "bar"})
               |> perform_job(prefix: "private")
    end
  end

  describe "perform_job/3" do
    test "verifying that the worker implements the Oban.Worker behaviour" do
      message = "worker to be a module that implements"

      assert_perform_error(BogusWorker, message)
      assert_perform_error(InvalidWorker, message)

      :ok = perform_job(DoubleBehaviourWorker, %{})
    end

    test "validating options used to construct a job changeset" do
      assert_perform_error(
        Worker,
        %{},
        [max_attempts: -1],
        "max_attempts: must be greater than 0"
      )

      assert_perform_error(Worker, %{}, [priority: -1], "priority: must be greater than -1")
    end

    test "passing non-map args through to an overridden new/2 function" do
      {:ok, %{"id" => 1}} = perform_job(OverriddenWorker, {:id, 1})
    end

    test "validating the return value of the worker's perform/1 function" do
      assert_perform_error(MisbehavedWorker, %{"action" => "bad_atom"}, ":bad")

      message = "Expected result to be one of"
      actions = ["bad_string", "bad_error", "bad_tuple", "bad_snooze"]

      for action <- actions do
        assert_perform_error(MisbehavedWorker, %{"action" => action}, message)
      end
    end

    test "returning the value of worker's perform/1 function" do
      assert :ok = perform_job(Worker, %{ref: 1, action: "OK"})
      assert {:cancel, _} = perform_job(Worker, %{ref: 1, action: "CANCEL"})
      assert :discard = perform_job(Worker, %{ref: 1, action: "DISCARD"})
      assert {:error, _} = perform_job(Worker, %{ref: 1, action: "ERROR"})
    end

    test "not rescuing unhandled exceptions" do
      assert_raise RuntimeError, fn ->
        perform_job(MisbehavedWorker, %{"action" => "bad_code"})
      end

      assert_raise RuntimeError, fn ->
        perform_job(MisbehavedWorker, %{"action" => "bad_code", "timeout" => 20})
      end
    end

    test "respecting a worker's timeout" do
      Process.flag(:trap_exit, true)

      perform_job(MisbehavedWorker, %{"action" => "bad_timing", "timeout" => 1})

      assert_receive {:EXIT, _pid, %Oban.TimeoutError{}}

      perform_job(MisbehavedWorker, %{"action" => "bad_timing", "timeout" => 20})

      refute_receive {:EXIT, _pid, %Oban.TimeoutError{}}
    end

    test "injecting a complete conf into the job before execution" do
      assert {:ok, conf} = perform_job(EchoWorker, %{field: :conf}, prefix: "private")

      assert %{prefix: "private"} = conf
    end

    test "generating a fake id for each attempt" do
      assert {:ok, id_1} = perform_job(EchoWorker, %{field: :id})
      assert {:ok, id_2} = perform_job(EchoWorker, %{field: :id})

      assert is_integer(id_1)
      assert is_integer(id_2)

      refute id_1 == id_2
    end

    test "round trip encoding map fields" do
      meta = %{check: :meta}

      assert {:ok, %{"field" => "args"}} = perform_job(EchoWorker, %{field: :args})
      assert {:ok, %{"check" => "meta"}} = perform_job(EchoWorker, %{field: :meta}, meta: meta)
    end

    test "splitting configuration options before building a changeset" do
      assert {:ok, _} = perform_job(EchoWorker, %{field: :id}, engine: Oban.Engines.Basic)
    end

    test "defaulting the number of attempts to mimic real execution" do
      assert {:ok, 1} = perform_job(AttemptDrivenWorker, %{})
      assert {:ok, 2} = perform_job(AttemptDrivenWorker, %{}, attempt: 2)
    end

    test "defaulting timestamp fields to mimic real execution" do
      assert {:ok, result} = perform_job(TemporalWorker, %{})

      assert %{attempted_at: %_{}, inserted_at: %_{}, scheduled_at: %_{}} = result
    end

    test "retaining attempted_at, scheduled_at and inserted_at timestamps" do
      time = ~U[2020-02-20 00:00:00.000000Z]

      assert {:ok, result} =
               perform_job(TemporalWorker, %{},
                 attempted_at: time,
                 inserted_at: time,
                 scheduled_at: time
               )

      assert result.attempted_at == time
      assert result.inserted_at == time
      assert result.scheduled_at == time
    end

    test "emitting appropriate telemetry events" do
      TelemetryHandler.attach_events()

      assert :ok = perform_job(Worker, %{ref: 1, action: "OK"})
      assert_receive {:event, :stop, _, %{job: %{args: %{"ref" => 1}}, state: :success}}

      assert {:error, _} = perform_job(Worker, %{ref: 2, action: "ERROR"})
      assert_receive {:event, :exception, _, %{job: %{args: %{"ref" => 2}}, state: :failure}}

      assert_raise RuntimeError, fn ->
        perform_job(Worker, %{ref: 3, action: "FAIL"})
      end

      assert_receive {:event, :exception, _, %{job: %{args: %{"ref" => 3}}, state: :failure}}
    end
  end

  describe "all_enqueued/0,1" do
    test "retrieving a filtered list of enqueued jobs" do
      insert!(%{id: 1, ref: "a"}, worker: Ping, queue: :alpha)
      insert!(%{id: 2, ref: "b"}, worker: Ping, queue: :alpha)
      insert!(%{id: 3, ref: "c"}, worker: Pong, queue: :gamma)

      assert [%{args: %{"id" => 2}} | _] = all_enqueued(worker: Ping)
      assert [%Job{}] = all_enqueued(worker: Pong, queue: :gamma)
      assert [%Job{}, %Job{}, %Job{}] = all_enqueued()
    end
  end

  describe "assert_enqueued/1" do
    test "checking for jobs with matching properties" do
      insert!(%{}, worker: Ping, queue: :omega)
      insert!(%{id: 1, xd: 1}, worker: Ping, queue: :alpha)
      insert!(%{id: 2, xd: 2}, worker: Pong, queue: :gamma)
      insert!(%{message: "hello"}, worker: Pong, queue: :gamma)

      assert_enqueued worker: Ping
      assert_enqueued worker: Ping, queue: :alpha
      assert_enqueued worker: Ping, queue: :alpha, args: %{id: 1}
      assert_enqueued worker: Pong
      assert_enqueued worker: "Pong", queue: "gamma"
      assert_enqueued worker: "Pong", queue: "gamma", args: %{message: "hello"}
      assert_enqueued args: %{}, queue: :omega
      assert_enqueued args: %{id: 1}
      assert_enqueued args: %{id: 1, xd: 1}
      assert_enqueued args: %{message: "hello"}
      assert_enqueued worker: Ping, prefix: "public"
    end

    test "checking for jobs with matching timestamps within delta" do
      insert!(%{}, worker: Ping)
      insert!(%{}, worker: Pong, scheduled_at: seconds_from_now(60))
      insert!(%{}, worker: Pong, scheduled_at: ~U[2000-10-20 05:10:31.057748Z])

      assert_enqueued worker: Ping, state: "available", scheduled_at: DateTime.utc_now()
      assert_enqueued worker: Ping, scheduled_at: DateTime.now!("America/Chicago")
      assert_enqueued worker: Pong, scheduled_at: seconds_from_now(60)
      assert_enqueued worker: Pong, scheduled_at: {seconds_from_now(69), delta: 10}
      assert_enqueued worker: Pong, scheduled_at: ~U[2000-10-20 05:10:30.557748Z]
    end

    test "asserting that jobs are now or will eventually be enqueued" do
      insert!(%{id: 1}, worker: Ping, queue: :alpha)

      Task.async(fn ->
        Process.sleep(10)

        insert!(%{id: 2}, worker: Pong, queue: :alpha)
      end)

      assert_enqueued [worker: Pong, args: %{id: 2}], 100
      assert_enqueued [worker: Ping, args: %{id: 1}], 100
    end

    test "printing a helpful error message" do
      insert!(%{dest: "some_node"}, worker: Ping)

      try do
        assert_enqueued worker: Ping, args: %{dest: "other_node"}
      rescue
        error in [ExUnit.AssertionError] ->
          expected = """
          Expected a job matching:

          %{args: %{dest: "other_node"}, worker: Ping}

          to be enqueued. Instead found:

          [%{args: %{"dest" => "some_node"}, worker: "Ping"}]
          """

          assert error.message == expected
      end
    end
  end

  describe "refute_enqueued/1" do
    test "refuting jobs with specific properties have been enqueued" do
      insert!(%{id: 1, xd: [1]}, worker: Ping, queue: :alpha)
      insert!(%{id: 2, xd: [2]}, worker: Pong, queue: :gamma)
      insert!(%{id: 3, xd: [3]}, worker: Pong, queue: :gamma, state: "completed")
      insert!(%{id: 4, xd: [4]}, worker: Pong, queue: :gamma, state: "discarded")
      insert!(%{message: "hello"}, worker: Pong, queue: :gamma)

      refute_enqueued worker: Pongo
      refute_enqueued worker: Ping, args: %{id: 2}
      refute_enqueued worker: Pong, args: %{id: 3}
      refute_enqueued worker: Pong, args: %{id: 4}
      refute_enqueued worker: Pong, args: %{xd: [2, 2]}
      refute_enqueued worker: Ping, queue: :gamma
      refute_enqueued worker: Pong, queue: :gamma, args: %{message: "helo"}
      refute_enqueued worker: Ping, prefix: "private"
    end

    test "checking for jobs with complex and nested args" do
      insert!(%{
        int: 1,
        atom: :foo,
        bool: true,
        string: "foo",
        date: ~D[2023-01-01],
        time: ~T[00:00:00],
        naive: ~N[2023-01-01 00:00:00],
        datetime: ~U[2023-01-01 00:00:00Z],
        list: [1, 2],
        map: %{
          int: 2,
          list: [3, 4],
          map: %{atom: :foo}
        }
      })

      assert_enqueued args: %{int: 1, atom: :foo, bool: true, string: "foo"}
      assert_enqueued args: %{date: ~D[2023-01-01], time: ~T[00:00:00]}
      assert_enqueued args: %{naive: ~N[2023-01-01 00:00:00], datetime: ~U[2023-01-01 00:00:00Z]}
      assert_enqueued args: %{list: [1, 2], map: %{int: 2}}
      assert_enqueued args: %{map: %{int: 2, list: [3, 4]}}
      assert_enqueued args: %{map: %{list: [3, 4], map: %{atom: "foo"}}}

      assert_enqueued args: %{map: :_}
      assert_enqueued args: %{map: %{int: :_}}
      assert_enqueued args: %{map: %{map: %{atom: :_}}}

      refute_enqueued args: %{int: 2, atom: :foo, bool: true, string: "foo"}
      refute_enqueued args: %{int: 1, atom: :bar, bool: true, string: "foo"}
      refute_enqueued args: %{int: 1, atom: :foo, bool: false, string: "foo"}
      refute_enqueued args: %{int: 1, atom: :foo, bool: true, string: "bar"}

      refute_enqueued args: %{date: ~D[2023-01-02]}
      refute_enqueued args: %{time: ~T[00:00:01]}
      refute_enqueued args: %{naive: ~N[2023-01-01 00:00:01]}
      refute_enqueued args: %{datetime: ~U[2023-01-01 00:00:01Z]}

      refute_enqueued args: %{map: %{int: 1}}
      refute_enqueued args: %{map: %{int: 2, list: [3]}}
      refute_enqueued args: %{map: %{int: 2, list: [3, 4], map: %{atom: :bar}}}
    end

    test "refuting that jobs will eventually be enqueued" do
      Task.async(fn ->
        Process.sleep(10)

        insert!(%{id: 1}, worker: Ping, queue: :alpha)
      end)

      refute_enqueued [worker: Ping, args: %{id: 1}], 5
    end
  end

  describe "with_testing_mode/2" do
    test "temporarily running with :inline mode" do
      name = start_supervised_oban!(testing: :manual)

      Testing.with_testing_mode(:inline, fn ->
        Oban.insert!(name, Worker.new(%{ref: 1, action: "OK"}))

        assert_received {:ok, 1}
      end)
    end

    test "temporarily running with :manual mode" do
      name = start_supervised_oban!(testing: :inline)

      Testing.with_testing_mode(:manual, fn ->
        Oban.insert!(name, Worker.new(%{ref: 1, action: "OK"}))

        assert_enqueued worker: Worker

        refute_received {:ok, 1}, 25
      end)
    end

    test "the temporary mode cascades down to child processes" do
      name = start_supervised_oban!(testing: :manual)

      Testing.with_testing_mode(:inline, fn ->
        fun = fn ->
          Oban.insert!(name, Worker.new(%{ref: 1, action: "OK"}))

          assert_received {:ok, 1}
        end

        fun
        |> Task.async()
        |> Task.await()
      end)
    end

    test "with perform_job" do
      Testing.with_testing_mode(:manual, fn ->
        assert :ok = perform_job(Worker, %{ref: 1, action: "OK"})
      end)

      Testing.with_testing_mode(:inline, fn ->
        assert :ok = perform_job(Worker, %{ref: 1, action: "OK"})
      end)
    end
  end

  defp assert_perform_error(worker, message) when is_binary(message) do
    assert_perform_error(worker, %{}, [], message)
  end

  defp assert_perform_error(worker, args, message) when is_binary(message) do
    assert_perform_error(worker, args, [], message)
  end

  defp assert_perform_error(worker, args, opts, message) do
    perform_job(worker, args, opts)

    assert false, "This should not be reached"
  rescue
    error in [ExUnit.AssertionError] -> assert error.message =~ message
  end
end
