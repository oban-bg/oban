defmodule Oban.Case do
  @moduledoc false

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox
  alias Oban.Integration.Worker
  alias Oban.Job
  alias Oban.Test.Repo

  using do
    quote do
      use ExUnitProperties

      import Oban.Case

      alias Oban.Integration.Worker
      alias Oban.{Config, Job, Peer}
      alias Oban.Test.Repo
    end
  end

  @delete_query """
  DO $$BEGIN
  DELETE FROM oban_jobs;
  DELETE FROM oban_peers;
  DELETE FROM private.oban_jobs;
  DELETE FROM private.oban_peers;
  END$$
  """

  setup tags do
    # Within Sandbox mode everything happens in a transaction, which prevents the use of
    # LISTEN/NOTIFY messages.
    if tags[:integration] do
      Repo.query!(@delete_query, [])

      on_exit(fn -> Repo.query!(@delete_query, []) end)
    else
      pid = Sandbox.start_owner!(Repo, shared: not tags[:async])

      on_exit(fn -> Sandbox.stop_owner(pid) end)
    end

    :ok
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
end
