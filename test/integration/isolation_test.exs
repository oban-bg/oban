defmodule Oban.Integration.IsolationTest do
  use Oban.Case

  @moduletag :integration

  test "multiple supervisors can be run simultaneously" do
    start_supervised!({Oban, name: ObanA, repo: Repo, queues: [alpha: 1]}, id: ObanA)
    start_supervised!({Oban, name: ObanB, repo: Repo, queues: [gamma: 1]}, id: ObanB)

    insert_job!(ref: 1, action: "OK")

    assert_receive {:ok, 1}

    stop_supervised(ObanA)
    stop_supervised(ObanB)
  end

  defp insert_job!(args) do
    args
    |> Worker.new(queue: :alpha)
    |> Repo.insert!()
  end
end
