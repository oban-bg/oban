if function_exported?(Code, :put_compiler_option, 2) do
  Code.put_compiler_option(:warnings_as_errors, true)
end

Logger.configure(level: :warn)

ExUnit.start()

Oban.Test.Repo.start_link()

defmodule Oban.Case do
  @moduledoc false

  use ExUnit.CaseTemplate

  alias Oban.Integration.Worker
  alias Oban.Job
  alias Oban.Test.Repo

  using do
    quote do
      use ExUnitProperties

      import Oban.Case

      alias Oban.Integration.Worker
      alias Oban.{Config, Job}
      alias Repo
    end
  end

  setup tags do
    # We are intentionally avoiding Sandbox mode for testing. Within Sandbox mode everything
    # happens in a transaction, which prevents the use of LISTEN/NOTIFY messages.
    if tags[:integration] do
      Repo.delete_all(Job)
      Repo.delete_all(Job, prefix: "private")

      on_exit(fn ->
        Repo.delete_all(Job)
        Repo.delete_all(Job, prefix: "private")
      end)
    end

    {:ok, %{}}
  end

  def start_supervised_oban!(opts) do
    opts =
      opts
      |> Keyword.put_new(:name, make_ref())
      |> Keyword.put_new(:repo, Repo)
      |> Keyword.put_new(:shutdown_grace_period, 1)

    name = opts[:name]

    start_supervised!({Oban, opts})

    name
  end

  def build(args, opts \\ []) do
    if opts[:worker] do
      Job.new(args, opts)
    else
      Worker.new(args, opts)
    end
  end

  def insert!(args, opts \\ []) do
    args
    |> build(opts)
    |> Repo.insert!()
  end

  def insert!(oban, args, opts) do
    changeset = build(args, opts)

    Oban.insert!(oban, changeset)
  end

  def seconds_from_now(seconds) do
    DateTime.add(DateTime.utc_now(), seconds, :second)
  end

  def seconds_ago(seconds) do
    DateTime.add(DateTime.utc_now(), -seconds)
  end

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
        reraise(exception, __STACKTRACE__)
      end
  end

  def mangle_jobs_table! do
    Repo.query!("ALTER TABLE oban_jobs RENAME TO oban_missing")
  end

  def reform_jobs_table! do
    Repo.query!("ALTER TABLE oban_missing RENAME TO oban_jobs")
  end
end
