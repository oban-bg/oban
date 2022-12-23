defmodule Oban.Integration.LiteTest do
  use Oban.Case, async: true

  alias Oban.Test.LiteRepo

  @moduletag lite: true

  test "inserting and executing jobs" do
    name =
      start_supervised_oban!(
        engine: Oban.Engines.Lite,
        poll_interval: 10,
        queues: [alpha: 3],
        repo: LiteRepo
      )

    changesets =
      ~w(OK CANCEL DISCARD ERROR SNOOZE)
      |> Enum.with_index(1)
      |> Enum.map(fn {act, ref} -> Worker.new(%{action: act, ref: ref}) end)

    [job_1, job_2, job_3, job_4, job_5] = Oban.insert_all(name, changesets)

    assert_receive {:ok, 1}
    assert_receive {:cancel, 2}
    assert_receive {:discard, 3}
    assert_receive {:error, 4}
    assert_receive {:snooze, 5}

    with_backoff(fn ->
      assert %{state: "completed", completed_at: %_{}} = LiteRepo.reload!(job_1)
      assert %{state: "cancelled", cancelled_at: %_{}} = LiteRepo.reload!(job_2)
      assert %{state: "discarded", discarded_at: %_{}} = LiteRepo.reload!(job_3)
      assert %{state: "retryable", scheduled_at: %_{}} = LiteRepo.reload!(job_4)
      assert %{state: "scheduled", scheduled_at: %_{}} = LiteRepo.reload!(job_5)
    end)
  end
end
