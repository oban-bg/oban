defmodule Oban.Case do
  @moduledoc false

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox
  alias Oban.Integration.Worker
  alias Oban.Job
  alias Oban.Test.{LiteRepo, Repo, UnboxedRepo}

  using do
    quote do
      import Oban.Case

      alias Oban.Integration.Worker
      alias Oban.{Config, Job}
      alias Oban.Test.{LiteRepo, Repo, UnboxedRepo}
    end
  end

  setup context do
    cond do
      context[:unboxed] ->
        on_exit(fn ->
          UnboxedRepo.delete_all(Oban.Job)
          UnboxedRepo.delete_all(Oban.Job, prefix: "private")
        end)

      context[:lite] ->
        on_exit(fn ->
          LiteRepo.delete_all(Oban.Job)
        end)

      true ->
        pid = Sandbox.start_owner!(Repo, shared: not context[:async])

        on_exit(fn -> Sandbox.stop_owner(pid) end)
    end

    :ok
  end

  def start_supervised_oban!(opts) do
    opts =
      opts
      |> Keyword.put_new(:name, make_ref())
      |> Keyword.put_new(:notifier, Oban.Notifiers.Isolated)
      |> Keyword.put_new(:peer, Oban.Peers.Isolated)
      |> Keyword.put_new(:stage_interval, :infinity)
      |> Keyword.put_new(:repo, Repo)
      |> Keyword.put_new(:shutdown_grace_period, 250)

    name = Keyword.fetch!(opts, :name)
    repo = Keyword.fetch!(opts, :repo)

    attach_auto_allow(repo, name)
    start_supervised!({Oban, opts})
    ensure_started(name, opts)

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

  defp attach_auto_allow(Repo, name) do
    telemetry_name = "oban-auto-allow-#{inspect(name)}"

    auto_allow = fn _event, _measure, %{conf: conf}, {name, repo, test_pid} ->
      if conf.name == name, do: Sandbox.allow(repo, test_pid, self())
    end

    :telemetry.attach_many(
      telemetry_name,
      [[:oban, :engine, :init, :start], [:oban, :plugin, :init]],
      auto_allow,
      {name, Repo, self()}
    )

    on_exit(name, fn -> :telemetry.detach(telemetry_name) end)
  end

  defp attach_auto_allow(_repo, _name), do: :ok

  defp ensure_started(name, opts) do
    opts
    |> Keyword.get(:queues, [])
    |> Keyword.keys()
    |> Enum.each(&Oban.check_queue(name, queue: &1))
  end
end
