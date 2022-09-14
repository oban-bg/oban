defmodule Oban.Integration.DatabaseTriggerTest do
  use Oban.Case

  @moduletag :unboxed

  test "dispatching jobs from a queue via database trigger" do
    name =
      start_supervised_oban!(
        notifier: Oban.Notifiers.Postgres,
        queues: [alpha: 5],
        repo: UnboxedRepo,
        prefix: "private"
      )

    Oban.insert!(name, Worker.new(%{ref: 1, action: "OK"}))

    assert_receive {:ok, 1}
  end
end
