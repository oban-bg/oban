defmodule Oban.Integration.DynamicRepoTest do
  use Oban.Case

  import Ecto.Query

  alias Oban.Test.DynamicRepo

  setup do
    {:ok, repo_pid} = start_supervised({DynamicRepo, name: nil})

    DynamicRepo.put_dynamic_repo(repo_pid)
    Repo.delete_all(Job)
    DynamicRepo.put_dynamic_repo(nil)

    on_exit(fn ->
      DynamicRepo.put_dynamic_repo(repo_pid)
      Repo.delete_all(Job)
    end)

    {:ok, repo_pid: repo_pid}
  end

  test "job execution", context do
    name = start_oban!(context.repo_pid, queues: [alpha: 1])
    job_ref = insert_job!(name).ref

    assert_receive {:ok, ^job_ref}
  end

  test "pruning", context do
    start_oban!(context.repo_pid, plugins: [{Oban.Plugins.Pruner, interval: 10, max_age: 60}])

    DynamicRepo.put_dynamic_repo(context.repo_pid)

    insert!(%{}, state: "completed", attempted_at: seconds_ago(62))

    with_backoff(fn -> assert retained_ids() == [] end)
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

  defp retained_ids do
    Job
    |> select([j], j.id)
    |> order_by(asc: :id)
    |> Repo.all()
  end
end
