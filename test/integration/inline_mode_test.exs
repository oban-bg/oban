defmodule Oban.Integration.InlineModeTest do
  use Oban.Case, async: true

  alias Ecto.Multi

  describe ":inline mode" do
    test "executing a single inserted job inline" do
      name = start_supervised_oban!(testing: :inline)

      assert {:ok, job_1} = Oban.insert(name, Worker.new(%{ref: 1, action: "OK"}))
      assert {:ok, job_2} = Oban.insert(name, Worker.new(%{ref: 2, action: "ERROR"}))
      assert {:ok, job_3} = Oban.insert(name, Worker.new(%{ref: 3, action: "SNOOZE"}))
      assert {:ok, job_4} = Oban.insert(name, Worker.new(%{ref: 4, action: "DISCARD"}))

      assert %{attempt: 1, completed_at: %_{}, state: "completed"} = job_1
      assert %{attempt: 1, scheduled_at: %_{}, errors: [_], state: "retryable"} = job_2
      assert %{attempt: 1, scheduled_at: %_{}, state: "scheduled"} = job_3
      assert %{attempt: 1, discarded_at: %_{}, state: "discarded"} = job_4

      assert_receive {:ok, 1}
      assert_receive {:error, 2}
      assert_receive {:snooze, 3}
      assert_receive {:discard, 4}
    end

    test "executing a job with errors raises" do
      name = start_supervised_oban!(testing: :inline)

      assert_raise RuntimeError, fn ->
        Oban.insert(name, Worker.new(%{ref: 1, action: "FAIL"}))
      end

      assert_raise Oban.CrashError, fn ->
        Oban.insert(name, Worker.new(%{ref: 1, action: "EXIT"}))
      end
    end

    test "executing single jobs inserted within a multi" do
      name = start_supervised_oban!(testing: :inline)

      multi = Multi.new()
      multi = Oban.insert(name, multi, :job_1, Worker.new(%{ref: 1, action: "OK"}))
      multi = Oban.insert(name, multi, :job_2, fn _ -> Worker.new(%{ref: 2, action: "OK"}) end)

      assert {:ok, %{job_1: _, job_2: _}} = Repo.transaction(multi)

      assert_receive {:ok, 1}
      assert_receive {:ok, 2}
    end

    test "executing multiple jobs inserted inline" do
      name = start_supervised_oban!(testing: :inline)

      jobs_1 = for ref <- 1..2, do: Worker.new(%{ref: ref, action: "OK"})
      jobs_2 = for ref <- 3..4, do: Worker.new(%{ref: ref, action: "OK"})

      assert [%Job{}, %Job{}] = Oban.insert_all(name, jobs_1)
      assert [%Job{}, %Job{}] = Oban.insert_all(name, %{changesets: jobs_2})

      assert_receive {:ok, 2}
      assert_receive {:ok, 4}
    end

    test "executing multiple jobs inserted within a multi" do
      name = start_supervised_oban!(testing: :inline)

      jobs_1 = for ref <- 1..2, do: Worker.new(%{ref: ref, action: "OK"})
      jobs_2 = for ref <- 3..4, do: Worker.new(%{ref: ref, action: "OK"})
      jobs_3 = for ref <- 5..6, do: Worker.new(%{ref: ref, action: "OK"})

      multi = Multi.new()
      multi = Oban.insert_all(name, multi, :jobs_1, jobs_1)
      multi = Oban.insert_all(name, multi, :jobs_2, %{changesets: jobs_2})
      multi = Oban.insert_all(name, multi, :jobs_3, fn _ -> jobs_3 end)

      assert {:ok, %{jobs_1: _, jobs_2: _, jobs_3: _}} = Repo.transaction(multi)

      assert_receive {:ok, 2}
      assert_receive {:ok, 4}
      assert_receive {:ok, 6}
    end
  end
end
