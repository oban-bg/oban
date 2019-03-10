Logger.configure(level: :info)

ExUnit.start()

Oban.Test.Repo.start_link()
Ecto.Adapters.SQL.Sandbox.mode(Oban.Test.Repo, :manual)

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

  alias Ecto.Adapters.SQL.Sandbox
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
    :ok = Sandbox.checkout(Repo)

    unless tags[:async] do
      Sandbox.mode(Repo, {:shared, self()})
    end

    {:ok, %{}}
  end
end
