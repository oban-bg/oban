defmodule Oban.Integration.CheckingTest do
  use Oban.Case

  @moduletag :integration

  test "checking on queue state at runtime" do
    name = start_supervised_oban!(queues: [alpha: 1, gamma: 2, delta: [limit: 2, paused: true]])

    insert!([ref: 1, sleep: 500], queue: :alpha)
    insert!([ref: 2, sleep: 500], queue: :gamma)

    assert_receive {:started, 1}
    assert_receive {:started, 2}

    alpha_state = Oban.check_queue(name, queue: :alpha)

    assert %{limit: 1, node: _, paused: false} = alpha_state
    assert %{queue: "alpha", running: [_], started_at: %DateTime{}} = alpha_state

    assert %{limit: 2, queue: "gamma", running: [_]} = Oban.check_queue(name, queue: :gamma)
    assert %{paused: true, queue: "delta", running: []} = Oban.check_queue(name, queue: :delta)
  end

  test "checking an unknown or invalid queue" do
    name = start_supervised_oban!(queues: [])

    assert_raise ArgumentError, fn -> Oban.check_queue(name, wrong: nil) end
    assert_raise ArgumentError, fn -> Oban.check_queue(name, queue: nil) end
  end
end
