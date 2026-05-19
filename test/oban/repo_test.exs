defmodule Oban.RepoTest do
  use Oban.Case, async: true

  import ExUnit.CaptureLog

  alias Oban.Config
  alias Oban.Test.DynamicRepo

  @moduletag :unboxed

  defmodule FailRepo do
    def __adapter__, do: Ecto.Adapters.Postgres

    def config, do: []

    def transaction(_fun, _opts) do
      raise DBConnection.ConnectionError, "boom"
    end
  end

  defmodule RepoTest.GhostRepo do
    def __adapter__, do: Ecto.Adapters.Postgres

    def config, do: []
  end

  test "retrying dispatch when the configured repo module is unavailable" do
    conf = Config.new(repo: RepoTest.GhostRepo)

    :code.purge(RepoTest.GhostRepo)
    :code.delete(RepoTest.GhostRepo)

    assert_raise UndefinedFunctionError, fn ->
      Oban.Repo.all(conf, Oban.Job)
    end
  end

  describe "transaction/3 retry exhaustion" do
    test "reraises the underlying error by default" do
      conf = Config.new(repo: FailRepo)

      capture_log(fn ->
        assert_raise DBConnection.ConnectionError, fn ->
          Oban.Repo.transaction(conf, fn -> :ok end, retry: 0)
        end
      end)
    end

    test "returns {:error, exception} and logs when on_exhausted is :log" do
      conf = Config.new(repo: FailRepo)

      log =
        capture_log(fn ->
          Oban.Repo.transaction(conf, fn -> :ok end, retry: 0, on_exhausted: :log)
        end)

      assert log =~ "DBConnection.ConnectionError"
    end
  end

  test "querying with a dynamic repo (MFA)" do
    {:ok, repo_pid} = start_supervised({DynamicRepo, name: nil})

    DynamicRepo.put_dynamic_repo(nil)

    name =
      start_supervised_oban!(
        get_dynamic_repo: {DynamicRepo, :use_dynamic_repo, [repo_pid]},
        repo: DynamicRepo
      )

    conf = Oban.config(name)

    assert is_integer(Oban.Repo.aggregate(conf, Oban.Job, :count))
  end

  test "querying with a dynamic repo (anonymous function)" do
    {:ok, repo_pid} = start_supervised({DynamicRepo, name: nil})

    DynamicRepo.put_dynamic_repo(nil)

    name = start_supervised_oban!(get_dynamic_repo: fn -> repo_pid end, repo: DynamicRepo)
    conf = Oban.config(name)

    assert is_integer(Oban.Repo.aggregate(conf, Oban.Job, :count))
  end
end
