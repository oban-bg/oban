defmodule Oban.Integration.ResiliencyTest do
  use Oban.Case

  @moduletag :integration

  test "retrying recording job completion after errors" do
    start_supervised_oban!(queues: [alpha: 1])

    job = insert!(ref: 1, sleep: 10)

    assert_receive {:started, 1}

    mangle_jobs_table!()

    assert_receive {:ok, 1}

    reform_jobs_table!()

    with_backoff([sleep: 50, total: 10], fn ->
      assert %{state: "completed"} = Repo.reload(job)
    end)
  end
end
