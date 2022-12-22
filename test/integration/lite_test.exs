defmodule Oban.Integration.LiteTest do
  use Oban.Case, async: true

  alias Oban.Test.LiteRepo

  @moduletag lite: true

  # TODO: Clean up after each run, there isn't a sandbox

  test "inserting and executing jobs" do
    name = start_supervised_oban!(
      engine: Oban.Engines.Lite,
      poll_interval: 10,
      queues: [alpha: 3],
      peer: Oban.Peers.Global,
      prefix: false,
      repo: LiteRepo
    )

    Oban.insert(name, Worker.new(%{action: "OK", ref: 1}))
    Oban.insert(name, Worker.new(%{action: "OK", ref: 2}))

    assert_receive {:ok, 1}
    assert_receive {:ok, 2}
  end
end
