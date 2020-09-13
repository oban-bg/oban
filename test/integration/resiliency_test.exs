defmodule Oban.Integration.ResiliencyTest do
  use Oban.Case

  @moduletag :integration

  defmodule Handler do
    def handle([:oban, :circuit, :trip], %{}, meta, pid) do
      send(pid, {:tripped, meta})
    end
  end

  setup do
    :telemetry.attach("circuit-handler", [:oban, :circuit, :trip], &Handler.handle/4, self())

    on_exit(fn -> :telemetry.detach("circuit-handler") end)
  end

  test "logging producer connection errors" do
    mangle_jobs_table!()

    start_supervised_oban!(queues: [alpha: 1])

    assert_receive {:tripped, %{message: message, name: name}}

    assert message =~ ~s|ERROR 42P01 (undefined_table)|
    assert name == Oban.Queue.Alpha.Producer
  after
    reform_jobs_table!()
  end

  test "reporting notification connection errors" do
    name = start_supervised_oban!(queues: [alpha: 1])

    assert %{conn: conn} = :sys.get_state(Oban.Registry.whereis(name, Oban.Notifier))
    assert Process.exit(conn, :forced_exit)

    # This verifies that producer's are isolated from the notifier
    insert!(ref: 1, action: "OK")

    assert_receive {:ok, 1}

    assert_receive {:tripped, %{message: ":forced_exit"}}
  end

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
