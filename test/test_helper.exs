Logger.configure(level: :warn)

ExUnit.start()

Oban.Test.Repo.start_link()

defmodule Oban.Integration.Worker do
  use Oban.Worker

  @impl Worker
  def new(args, opts) do
    opts = Keyword.merge(__opts__(), opts)

    args
    |> Map.new()
    |> Map.put_new(:bin_pid, pid_to_bin())
    |> Job.new(opts)
  end

  @impl Worker
  def perform(%{"ref" => ref, "action" => action, "bin_pid" => bin_pid}, _job) do
    pid = bin_to_pid(bin_pid)

    case action do
      "OK" ->
        send(pid, {:ok, ref})

        :ok

      "DISCARD" ->
        send(pid, {:discard, ref})

        :discard

      "ERROR" ->
        send(pid, {:error, ref})

        {:error, "ERROR"}

      "EXIT" ->
        send(pid, {:exit, ref})

        GenServer.call(FakeServer, :exit)

      "FAIL" ->
        send(pid, {:fail, ref})

        raise RuntimeError, "FAILED"

        :ok

      "SNOOZE" ->
        send(pid, {:snooze, ref})

        {:snooze, 60}

      "TASK_ERROR" ->
        send(pid, {:async, ref})

        fn -> apply(FakeServer, :call, []) end
        |> Task.async()
        |> Task.await()

        :ok
    end
  end

  def perform(%{"ref" => ref, "sleep" => sleep, "bin_pid" => bin_pid}, _job) do
    pid = bin_to_pid(bin_pid)

    send(pid, {:started, ref})

    :ok = Process.sleep(sleep)

    send(pid, {:ok, ref})

    :ok
  end

  @impl Worker
  def backoff(%_{args: %{"backoff" => backoff}}), do: backoff
  def backoff(%_{attempt: attempt}), do: Worker.backoff(attempt)

  @impl Worker
  def timeout(%_{args: %{"timeout" => timeout}}), do: timeout
  def timeout(_job), do: :infinity

  def pid_to_bin(pid \\ self()) do
    pid
    |> :erlang.term_to_binary()
    |> Base.encode64()
  end

  def bin_to_pid(bin) do
    bin
    |> Base.decode64!()
    |> :erlang.binary_to_term()
  end
end

defmodule Oban.Case do
  @moduledoc false

  use ExUnit.CaseTemplate

  alias Oban.Job
  alias Oban.Test.Repo

  using do
    quote do
      use ExUnitProperties

      import Oban.Case

      alias Oban.Integration.Worker
      alias Oban.{Config, Job}
      alias Repo

      def with_backoff(opts \\ [], fun) do
        total = Keyword.get(opts, :total, 100)
        sleep = Keyword.get(opts, :sleep, 10)

        with_backoff(fun, 0, total, sleep)
      end

      def with_backoff(fun, count, total, sleep) do
        fun.()
      rescue
        exception in [ExUnit.AssertionError] ->
          if count < total do
            Process.sleep(sleep)

            with_backoff(fun, count + 1, total, sleep)
          else
            reraise(exception, System.stacktrace())
          end
      end
    end
  end

  setup tags do
    # We are intentionally avoiding Sandbox mode for testing. Within Sandbox mode everything
    # happens in a transaction, which prevents the use of LISTEN/NOTIFY messages.
    if tags[:integration] do
      Repo.delete_all(Job)

      on_exit(fn ->
        Repo.delete_all(Job)
      end)
    end

    {:ok, %{}}
  end

  def seconds_from_now(seconds) do
    DateTime.add(DateTime.utc_now(), seconds, :second)
  end

  def seconds_ago(seconds) do
    DateTime.add(DateTime.utc_now(), -seconds)
  end
end
