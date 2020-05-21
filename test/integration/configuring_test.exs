defmodule Oban.Integration.ConfiguringTest do
  use Oban.Case

  @moduletag :integration

  test "configuring queue limits and poll intervals" do
    start_supervised_oban!(
      poll_interval: 25,
      dispatch_cooldown: 1,
      queues: [
        alpha: 1,
        gamma: [limit: 2, poll_interval: 10, dispatch_cooldown: 5],
        delta: [limit: 1, poll_interval: 5_000]
      ]
    )

    # Alpha polls every 25ms, only one of these will start
    insert!([ref: 1, sleep: 2_000], queue: :alpha)
    insert!([ref: 2, sleep: 2_000], queue: :alpha)
    insert!([ref: 3, sleep: 2_000], queue: :alpha)

    assert_receive {:started, 1}
    refute_receive {:started, 2}
    refute_receive {:started, 3}

    # Gamma polls every 10ms, all three of these will start
    insert!([ref: 4, sleep: 5], queue: :gamma)
    insert!([ref: 5, sleep: 5], queue: :gamma)
    insert!([ref: 6, sleep: 5], queue: :gamma)

    assert_receive {:started, 4}
    assert_receive {:started, 5}
    assert_receive {:started, 6}

    # Delta polls every 5_000ms, none one of these will start
    insert!([ref: 7, sleep: 500], queue: :delta)
    insert!([ref: 8, sleep: 500], queue: :delta)
    insert!([ref: 9, sleep: 500], queue: :delta)

    assert_receive {:started, 7}
    refute_receive {:started, 8}
    refute_receive {:started, 9}
  end
end
