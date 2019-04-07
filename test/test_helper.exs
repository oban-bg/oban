Logger.configure(level: :info)

ExUnit.start()

Application.put_env(:oban, Oban.Test.Repo,
  priv: "test/support/",
  url: System.get_env("DATABASE_URL") || "postgres://localhost:5432/oban_test"
)

Oban.Test.Repo.start_link()

defmodule Oban.Integration.Worker do
  use Oban.Worker

  @impl Worker
  def perform(%{"ref" => ref, "action" => action, "bin_pid" => bin_pid}) do
    pid = bin_to_pid(bin_pid)

    case action do
      "OK" ->
        send(pid, {:ok, ref})

      "FAIL" ->
        send(pid, {:fail, ref})

        raise RuntimeError, "FAILED"

      "EXIT" ->
        send(pid, {:exit, ref})

        GenServer.call(FakeServer, :exit)
    end
  end

  def perform(%{"ref" => ref, "sleep" => sleep, "bin_pid" => bin_pid}) do
    pid = bin_to_pid(bin_pid)

    send(pid, {:started, ref})

    :ok = Process.sleep(sleep)

    send(pid, {:ok, ref})
  end

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
      alias Oban.Integration.Worker
      alias Oban.Job
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

      on_exit(fn -> Repo.delete_all(Job) end)
    end

    {:ok, %{}}
  end
end
