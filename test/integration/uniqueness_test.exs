defmodule Oban.Integration.UniquenessTest do
  use Oban.Case

  import Ecto.Query

  alias Ecto.Multi

  @moduletag :integration

  @oban_opts repo: Repo, queues: [alpha: 5]

  defmodule UniqueWorker do
    use Oban.Worker, queue: :upsilon, unique: [period: 30]

    @impl Worker
    def perform(_args, _job), do: :ok
  end

  setup do
    start_supervised!({Oban, @oban_opts})

    :ok
  end

  property "preventing the same job from being enqueued multiple times" do
    check all args <- arg_map(), max_runs: 20 do
      assert insert_job!(args).id == insert_job!(args).id
    end
  end

  test "scoping uniqueness to particular fields" do
    assert %Job{id: id_1} = insert_job!(%{id: 1}, queue: "default")
    assert %Job{id: id_2} = insert_job!(%{id: 2}, queue: "delta")
    assert %Job{id: ^id_2} = insert_job!(%{id: 1}, unique: [fields: [:worker]])

    assert %Job{id: ^id_1} =
             insert_job!(%{id: 3}, queue: "default", unique: [fields: [:queue, :worker]])

    assert %Job{id: ^id_2} =
             insert_job!(%{id: 3}, queue: "delta", unique: [fields: [:queue, :worker]])

    assert count_jobs() == 2
  end

  test "scoping uniqueness by state" do
    assert %Job{id: id_1} = insert_job!(%{id: 1}, state: "available")
    assert %Job{id: id_2} = insert_job!(%{id: 2}, state: "completed")
    assert %Job{id: id_3} = insert_job!(%{id: 3}, state: "executing")
    assert %Job{id: ^id_1} = insert_job!(%{id: 1}, unique: [states: [:available]])
    assert %Job{id: ^id_2} = insert_job!(%{id: 2}, unique: [states: [:available, :completed]])
    assert %Job{id: ^id_3} = insert_job!(%{id: 3}, unique: [states: [:completed, :executing]])

    assert count_jobs() == 3
  end

  test "scoping uniqueness by period" do
    now = DateTime.utc_now()
    two_minutes_ago = DateTime.add(now, -120, :second)
    five_minutes_ago = DateTime.add(now, -300, :second)

    assert %Job{id: _id} = insert_job!(%{id: 1}, inserted_at: two_minutes_ago)
    assert %Job{id: _id} = insert_job!(%{id: 2}, inserted_at: five_minutes_ago)
    assert %Job{id: id_1} = insert_job!(%{id: 1}, unique: [period: 110])
    assert %Job{id: id_2} = insert_job!(%{id: 2}, unique: [period: 290])
    assert %Job{id: ^id_1} = insert_job!(%{id: 1}, unique: [period: 180])
    assert %Job{id: ^id_2} = insert_job!(%{id: 2}, unique: [period: 400])

    assert count_jobs() == 4
  end

  test "inserting unique jobs within a multi transaction" do
    assert {:ok, %{job_1: job_1, job_2: job_2, job_3: job_3}} =
             Multi.new()
             |> Oban.insert(:job_1, UniqueWorker.new(%{id: 1}))
             |> Oban.insert(:job_2, UniqueWorker.new(%{id: 2}))
             |> Oban.insert(:job_3, UniqueWorker.new(%{id: 1}))
             |> Repo.transaction()

    assert job_1.id != job_2.id
    assert job_1.id == job_3.id

    assert count_jobs() == 2
  end

  test "inserting multiple unique jobs in a single call" do
    # is there a property for this?
  end

  def arg_map, do: map_of(arg_key(), arg_val())
  def arg_key, do: one_of([integer(), string(:ascii)])
  def arg_val, do: one_of([integer(), string(:ascii), list_of(integer())])

  defp insert_job!(args, opts \\ []) do
    args
    |> UniqueWorker.new(opts)
    |> Oban.insert!()
  end

  defp count_jobs do
    Job
    |> select([j], count(j.id))
    |> Repo.one()
  end
end
