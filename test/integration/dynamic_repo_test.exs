defmodule Oban.Integration.DynamicRepoTest do
  use Oban.Case

  import Ecto.Query

  alias Oban.Test.DynamicRepo

  setup do
    {:ok, repo_pid} = start_supervised({DynamicRepo, name: nil})

    DynamicRepo.put_dynamic_repo(repo_pid)
    DynamicRepo.put_dynamic_repo(nil)

    on_exit(fn ->
      DynamicRepo.put_dynamic_repo(repo_pid)
    end)

    {:ok, repo_pid: repo_pid}
  end

  test "job execution", context do
    name = start_oban!(context.repo_pid, queues: [alpha: 1])
    job_ref = insert_job!(name).ref

    assert_receive {:ok, ^job_ref}
  end

  test "rollback job insertion after transaction failure", context do
    name = start_oban!(context.repo_pid, queues: [alpha: 1])

    {:ok, _app_repo_pid} =
      start_supervised(%{DynamicRepo.child_spec(name: :app_repo) | id: :app_repo})

    DynamicRepo.put_dynamic_repo(:app_repo)

    ref = System.unique_integer([:positive, :monotonic])

    assert {:error, :failure, :wat, %{job: %Oban.Job{args: %{ref: ^ref, action: "OK"}}}} =
             name
             |> Oban.insert(Ecto.Multi.new(), :job, Worker.new(%{ref: ref, action: "OK"}))
             |> Ecto.Multi.run(:failure, fn _repo, _ -> {:error, :wat} end)
             |> DynamicRepo.transaction()

    refute_receive {:ok, ^ref}
  end

  defp start_oban!(repo_pid, opts) do
    opts
    |> Keyword.merge(repo: DynamicRepo, get_dynamic_repo: fn -> repo_pid end)
    |> start_supervised_oban!()
  end

  defp insert_job!(oban_name) do
    ref = System.unique_integer([:positive, :monotonic])
    {:ok, job} = Oban.insert(oban_name, Worker.new(%{ref: ref, action: "OK"}))
    %{ref: ref, job: job}
  end
end
