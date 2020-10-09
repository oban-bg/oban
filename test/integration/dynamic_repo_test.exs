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

  test "draining", context do
    name = start_oban!(context.repo_pid, queues: false)
    job_ref = insert_job!(name).ref

    assert Oban.drain_queue(name, queue: :alpha) == %{failure: 0, success: 1}
    assert_receive {:ok, ^job_ref}
  end

  test "pruning", context do
    start_oban!(context.repo_pid, plugins: [{Oban.Plugins.Pruner, interval: 10, max_age: 60}])

    DynamicRepo.put_dynamic_repo(context.repo_pid)
    insert!(%{}, state: "completed", attempted_at: seconds_ago(62))

    with_backoff(fn -> assert retained_ids() == [] end)
  end

  test "cron", context do
    ref = System.unique_integer([:positive, :monotonic])

    start_oban!(
      context.repo_pid,
      queues: [alpha: 1],
      crontab: [
        {"* * * * *", Worker, args: %{ref: ref, action: "OK", bin_pid: Worker.pid_to_bin()}}
      ]
    )

    assert_receive {:ok, ^ref}
  end

  test "telemetry", context do
    name = start_oban!(context.repo_pid, queues: [alpha: 1])
    events = [[:oban, :job, :start], [:oban, :job, :stop], [:oban, :job, :exception]]
    :telemetry.attach_many("job-handler", events, &__MODULE__.TelemetryHandler.handle/4, self())

    job_id = insert_job!(name).job.id
    assert_receive {:event, :start, _started_time, %{id: ^job_id}}
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

  defmodule TelemetryHandler do
    def handle([:oban, :job, :start], %{system_time: start_time}, meta, pid) do
      send(pid, {:event, :start, start_time, meta})
    end

    def handle([:oban, :job, :stop], event_measurements, meta, pid) do
      send(pid, {:event, :stop, event_measurements, meta})
    end

    def handle([:oban, :job, event], %{duration: duration}, meta, pid) do
      send(pid, {:event, event, duration, meta})
    end
  end
end
