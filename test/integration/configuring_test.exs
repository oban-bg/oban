defmodule Oban.Integration.ConfiguringTest do
  use Oban.Case

  @moduletag :integration

  test "configuring queue limits and poll intervals" do
    name =
      start_supervised_oban!(
        dispatch_cooldown: 1,
        queues: [
          alpha: 1,
          gamma: [limit: 1, dispatch_cooldown: 5],
          omega: [limit: 1, paused: true]
        ]
      )

    with_backoff(fn ->
      assert %{limit: 1} = Oban.check_queue(name, queue: :alpha)
      assert %{limit: 1} = Oban.check_queue(name, queue: :gamma)
      assert %{limit: 1, paused: true} = Oban.check_queue(name, queue: :omega)
    end)
  end
end
