defmodule Oban.Integration.ConfiguringTest do
  use Oban.Case

  @moduletag :integration

  test "configuring queue limits and poll intervals" do
    start_supervised_oban!(
      dispatch_cooldown: 1,
      queues: [
        alpha: 1,
        gamma: [limit: 1, dispatch_cooldown: 5],
        omega: [limit: 1, paused: true]
      ]
    )

    # Alpha has limit 1, only one of these will start
    insert!([ref: 1, sleep: 1_000], queue: :alpha)
    insert!([ref: 2, sleep: 1_000], queue: :alpha)

    assert_receive {:started, 1}
    refute_receive {:started, 2}

    # Gamma has limit 1, all only two of these will start
    insert!([ref: 3, sleep: 1_000], queue: :gamma)
    insert!([ref: 4, sleep: 1_000], queue: :gamma)

    assert_receive {:started, 3}
    refute_receive {:started, 4}

    # Omega is paused, this won't start
    insert!([ref: 5, sleep: 5], queue: :omega)

    refute_receive {:started, 5}
  end
end
