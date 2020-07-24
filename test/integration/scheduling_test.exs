defmodule Oban.Integration.SchedulingTest do
  use Oban.Case

  @moduletag :integration

  test "descheduling jobs to make them available for execution" do
    _job_ = insert!([ref: 1, sleep: 5000], schedule_in: -9, queue: :alpha)
    _job_ = insert!([ref: 2, sleep: 5000], schedule_in: -5, queue: :alpha)
    job_3 = insert!([ref: 3, sleep: 5000], schedule_in: -1, queue: :alpha)
    job_4 = insert!([ref: 4, sleep: 5000], schedule_in: -1, queue: :gamma)
    job_5 = insert!([ref: 5, sleep: 5000], schedule_in: 10, queue: :alpha)

    start_supervised_oban!(queues: [alpha: 2])

    assert_receive {:started, 1}
    assert_receive {:started, 2}

    # Not started because the queue limit is 2
    refute_received {:started, 3}

    # Not descheduled because it is in a different queue
    refute_received {:started, 4}

    # Not descheduled because it is in the future
    refute_received {:started, 5}

    stop_supervised(Oban)

    assert %{state: "available"} = Repo.reload(job_3)
    assert %{state: "scheduled"} = Repo.reload(job_4)
    assert %{state: "scheduled"} = Repo.reload(job_5)
  end
end
