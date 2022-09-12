defmodule Oban.Case do
  @moduledoc false

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox
  alias Oban.Integration.Worker
  alias Oban.Job
  alias Oban.Test.Repo

  defmodule Peer do
    @moduledoc false

    def start_link(opts), do: Agent.start_link(fn -> true end, name: opts[:name])

    def leader?(pid, _timeout), do: Agent.get(pid, & &1)
  end

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
      |> Keyword.put_new(:notifier, Oban.Notifiers.PG)
      |> Keyword.put_new(:peer, Oban.Case.Peer)
      |> Keyword.put_new(:poll_interval, :infinity)
      |> Keyword.put_new(:repo, Repo)
      |> Keyword.put_new(:shutdown_grace_period, 250)

    name = Keyword.fetch!(opts, :name)
    repo = Keyword.fetch!(opts, :repo)

    attach_auto_allow(repo, name)

    start_supervised!({Oban, opts})

    name
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

  # Building

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

  # Time

  def seconds_from_now(seconds) do
    DateTime.add(DateTime.utc_now(), seconds, :second)
  end

  def seconds_ago(seconds) do
    DateTime.add(DateTime.utc_now(), -seconds)
  end

  # Attaching

  defp attach_auto_allow(repo, name) do
    telemetry_name = "oban-auto-allow-#{inspect(name)}"

    auto_allow = fn _event, _measure, %{conf: conf}, {name, repo, test_pid} ->
      if conf.name == name, do: Sandbox.allow(repo, test_pid, self())
    end

    :telemetry.attach_many(
      telemetry_name,
      [[:oban, :engine, :init, :start], [:oban, :plugin, :init]],
      auto_allow,
      {name, repo, self()}
    )

    on_exit(name, fn -> :telemetry.detach(telemetry_name) end)
  end
end
