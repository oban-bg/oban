defmodule Oban.Integration.IsolationTest do
  use Oban.Case

  use Oban.Testing, repo: Oban.Test.Repo

  @moduletag :integration

  test "multiple supervisors can be run simultaneously" do
    start_supervised!({Oban, name: ObanA, repo: Repo, queues: [alpha: 1]}, id: ObanA)
    start_supervised!({Oban, name: ObanB, repo: Repo, queues: [gamma: 1]}, id: ObanB)

    insert!(ObanA, %{ref: 1, action: "OK"}, [])

    assert_receive {:ok, 1}

    stop_supervised(ObanA)
    stop_supervised(ObanB)
  end

  test "inserting and executing jobs with a custom prefix" do
    start_supervised!({Oban, prefix: "private", repo: Repo, queues: [alpha: 5]})

    job = insert!(Oban, %{ref: 1, action: "OK"}, [])

    assert Ecto.get_meta(job, :prefix) == "private"

    assert_receive {:ok, 1}

    stop_supervised(Oban)
  end

  test "inserting and executing unique jobs with a custom prefix" do
    # Make sure the public table isn't available when we're attempting to query
    mangle_jobs_table!()

    start_supervised!({Oban, prefix: "private", repo: Repo, queues: [alpha: 5]})

    insert!(Oban, %{ref: 1, action: "OK"}, unique: [period: 60, fields: [:worker]])
    insert!(Oban, %{ref: 2, action: "OK"}, unique: [period: 60, fields: [:worker]])

    assert_receive {:ok, 1}
    refute_receive {:ok, 2}

    stop_supervised(Oban)
  after
    reform_jobs_table!()
  end

  defp insert!(oban, args, opts) do
    changeset = build(args, opts)

    Oban.insert!(oban, changeset)
  end
end
