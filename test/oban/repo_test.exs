defmodule Oban.RepoTest do
  use Oban.Case, async: true

  alias Oban.Test.DynamicRepo

  @moduletag :unboxed

  test "querying with a dynamic repo (MFA)" do
    {:ok, repo_pid} = start_supervised({DynamicRepo, name: nil})

    DynamicRepo.put_dynamic_repo(nil)

    name =
      start_supervised_oban!(
        get_dynamic_repo: {DynamicRepo, :use_dynamic_repo, [repo_pid]},
        repo: DynamicRepo
      )

    conf = Oban.config(name)

    Oban.Repo.insert!(conf, Worker.new(%{ref: 1, action: "OK"}))
  end

  test "querying with a dynamic repo (anonymous function)" do
    {:ok, repo_pid} = start_supervised({DynamicRepo, name: nil})

    DynamicRepo.put_dynamic_repo(nil)

    name = start_supervised_oban!(get_dynamic_repo: fn -> repo_pid end, repo: DynamicRepo)
    conf = Oban.config(name)

    Oban.Repo.insert!(conf, Worker.new(%{ref: 1, action: "OK"}))
  end
end
