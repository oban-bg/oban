defmodule Oban.Integration.DynamicRepoTest do
  use Oban.Case

  alias Oban.Test.DynamicRepo

  @moduletag :unboxed

  test "executing jobs using a dynamic repo" do
    {:ok, repo_pid} = start_supervised({DynamicRepo, name: nil})

    DynamicRepo.put_dynamic_repo(nil)

    on_exit(fn -> DynamicRepo.put_dynamic_repo(repo_pid) end)

    name = make_ref()

    opts = [
      get_dynamic_repo: fn -> repo_pid end,
      name: name,
      peer: Oban.Case.Peer,
      queues: [alpha: 1],
      repo: DynamicRepo,
    ]

    start_supervised!({Oban, opts})

    Oban.insert!(name, Worker.new(%{ref: 1, action: "OK"}))

    assert_receive {:ok, 1}
  end
end
