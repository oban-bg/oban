defmodule Oban.Integration.IsolationTest do
  use Oban.Case

  use Oban.Testing, repo: Oban.Test.Repo, prefix: "private"

  @moduletag :integration

  test "inserting jobs with a custom prefix" do
    name = start_supervised_oban!(prefix: "private")

    insert!(name, %{ref: 1, action: "OK"}, [])

    assert_enqueued worker: Worker
  end

  test "inserting and executing unique jobs with a custom prefix" do
    name = start_supervised_oban!(prefix: "private", queues: [alpha: 5])

    insert!(name, %{ref: 1, action: "OK"}, unique: [period: 60, fields: [:worker]])
    insert!(name, %{ref: 2, action: "OK"}, unique: [period: 60, fields: [:worker]])

    assert_receive {:ok, 1}
    refute_receive {:ok, 2}
  end
end
