defmodule Oban.Plugins.StagerTest do
  use Oban.Case

  alias Oban.Plugins.Stager
  alias Oban.Registry

  @moduletag :integration

  test "descheduling jobs to make them available for execution" do
    job_1 = insert!([ref: 1, action: "OK"], schedule_in: -9, queue: :alpha)
    job_2 = insert!([ref: 2, action: "OK"], schedule_in: -5, queue: :alpha)
    job_3 = insert!([ref: 3, action: "OK"], schedule_in: 10, queue: :alpha)

    start_supervised_oban!(plugins: [{Stager, interval: 10}])

    with_backoff(fn ->
      assert %{state: "available"} = Repo.reload(job_1)
      assert %{state: "available"} = Repo.reload(job_2)
      assert %{state: "scheduled"} = Repo.reload(job_3)
    end)
  end

  test "translating poll_interval config into plugin usage" do
    assert []
           |> start_supervised_oban!()
           |> Registry.whereis({:plugin, Stager})

    assert [poll_interval: 2000]
           |> start_supervised_oban!()
           |> Registry.whereis({:plugin, Stager})

    refute [plugins: false, poll_interval: 2000]
           |> start_supervised_oban!()
           |> Registry.whereis({:plugin, Stager})
  end
end
