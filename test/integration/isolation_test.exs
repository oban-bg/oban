defmodule Oban.Integration.IsolationTest do
  use Oban.Case

  use Oban.Testing, repo: Oban.Test.Repo

  @moduletag :integration

  test "multiple supervisors can be run simultaneously" do
    start_supervised!({Oban, name: ObanA, repo: Repo, queues: [alpha: 1]}, id: ObanA)
    start_supervised!({Oban, name: ObanB, repo: Repo, queues: [gamma: 1]}, id: ObanB)

    insert_job!(ObanA, ref: 1, action: "OK")

    assert_receive {:ok, 1}

    stop_supervised(ObanA)
    stop_supervised(ObanB)
  end

  test "inserting and executing jobs with a custom prefix" do
    start_supervised!({Oban, prefix: "private", repo: Repo, queues: [alpha: 5]})

    job = insert_job!(ref: 1, action: "OK")

    assert Ecto.get_meta(job, :prefix) == "private"

    assert_receive {:ok, 1}

    :ok = stop_supervised(Oban)
  end

  defp insert_job!(oban \\ Oban, args) do
    job = Worker.new(args, queue: :alpha)

    Oban.insert!(oban, job)
  end
end
